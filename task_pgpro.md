# Тестовое задание Postgres Professional

Для начала проведем анализ баз данных для более точной оценки расчетных данных.

```sql
vacuum full analyze t1;
vacuum full analyze t2;
```

## Задача 1

### Задание

[1] ускорить простой запроc, добиться времени выполнения < 10ms

```sql
select name from t1 where id = 50000;
```

### Ответ

При выполнении команды `explain analyze select name from t1 where id = 50000;`

Получаем вывод:

```
 Seq Scan on t1  (cost=0.00..208396.61 rows=1 width=30) (actual time=19.145..2112.412 rows=1 loops=1)
   Filter: (id = 50000)
   Rows Removed by Filter: 9999999
 Planning Time: 0.076 ms
 JIT:
   Functions: 4
   Options: Inlining false, Optimization false, Expressions true, Deforming true
   Timing: Generation 0.553 ms (Deform 0.303 ms), Inlining 0.000 ms, Optimization 0.469 ms, Emission 7.
397 ms, Total 8.419 ms
 Execution Time: 2113.098 ms
(9 rows)
```

Из анализа запроса видно, что идет последовательный поиск по полю `id`. Для ускорения запроса можно провести индексацию поля `id` для получения сканирования по индексу.

```sql
create index t1_id_idx on t1(id);
```

После индексации поля мы получаем, что запрос выполения по индексу и выполняется достаточно быстро.

```
 Index Scan using t1_id_idx on t1  (cost=0.43..8.45 rows=1 width=30) (actual time=0.035..0.038 rows=1 loops=1)
   Index Cond: (id = 50000)
 Planning Time: 0.102 ms
 Execution Time: 0.064 ms
(4 rows)
```


Для приведения статистики воспользуемся `pgbench` и запустим 100 запросов с 1 клиента.

```sql
pgbench -U postgres -d test -c 1 -t 100 -n -f task1.sql
```

После выполнения получаем ответ:

```
number of transactions per client: 100
number of transactions actually processed: 100/100
number of failed transactions: 0 (0.000%)
latency average = 0.226 ms
initial connection time = 5.543 ms
tps = 4416.766044 (without initial connection time)
```

## Задача 2

### Задание

[2] ускорить запрос "max + left join", добиться времени выполнения < 10ms

```sql
select max(t2.day) from t2 left join t1 on t2.t_id = t1.id and t1.name like 'a%';
```

### Ответ

Проанализируем выполнение команды.

```
 Aggregate  (cost=385602.04..385602.05 rows=1 width=32) (actual time=2862.122..2862.124 rows=1 loops=1)
   ->  Hash Left Join  (cost=218275.88..373102.06 rows=4999992 width=9) (actual time=733.367..2241.929 rows=5000000 loops=1)
         Hash Cond: (t2.t_id = t1.id)
         ->  Seq Scan on t2  (cost=0.00..81847.92 rows=4999992 width=13) (actual time=7.166..389.507 rows=5000000 loops=1)
         ->  Hash  (cost=208332.23..208332.23 rows=606052 width=4) (actual time=726.085..726.086 rows=625375 loops=1)
               Buckets: 262144  Batches: 4  Memory Usage: 7537kB
               ->  Seq Scan on t1  (cost=0.00..208332.23 rows=606052 width=4) (actual time=0.017..662.167 rows=625375 loops=1)
                     Filter: (name ~~ 'a%'::text)
                     Rows Removed by Filter: 9374625
 Planning Time: 0.390 ms
 JIT:
   Functions: 13
   Options: Inlining false, Optimization false, Expressions true, Deforming true
   Timing: Generation 1.352 ms (Deform 0.500 ms), Inlining 0.000 ms, Optimization 0.766 ms, Emission 6.327 ms, Total 8.445 ms
 Execution Time: 2863.618 ms
(15 rows)
```

Использование `left join` применяется для большого количества данных и высокая селективность запроса делаем индексные сканы неэффективные. Для эффективного запроса создадим индексы для необходимых полей и вместо последовательного обхода для получение максимума возьмем первое значение отсортированное по убыванию.

```sql
create index t1_id_name_idx on t1(id, name) where name like 'a%';

create index t2_day_t_id_idx on t2(day, t_id);
```

```sql
select day from t2 where t_id in (select id from t1 where name like 'a%') order by day DESC LIMIT 1;
```

После выполнения получаем результат:

```
number of transactions per client: 100
number of transactions actually processed: 100/100
number of failed transactions: 0 (0.000%)
latency average = 0.156 ms
initial connection time = 1.355 ms
tps = 6427.148274 (without initial connection time)
```


Так же можно создать `materialized view`, если запрос не будет изменяться и получить заранее известные данные.

```sql
create materialized view t2_day_like_a_view as select max(t2.day) from t2 left join t1 on t2.t_id = t1.id and t1.name like 'a%';
```

## Задача 3

### Задание

[3] ускорить запрос "anti-join", добиться времени выполнения < 10sec

```sql
select day from t2 where t_id not in ( select t1.id from t1 );
```

###  Ответ


Для оптимизации данного запроса его необходимо переписать вместо последовательного перебора последовательности `IN` на общую проверку полей. Для оптимизации запроса можно использовать `where not exists` либо `left join`.

переписать anti join NOT IN (...)

```sql
select day from t2 where not exists (select 1 from t1 where t1.id = t2.t_id);
```

```sql
select day from t2 left join t1 on t1.id = t2.t_id where t1.id is null;
```

После выполнения получаем результат:

```
number of transactions per client: 100
number of transactions actually processed: 100/100
number of failed transactions: 0 (0.000%)
latency average = 3155.589 ms
initial connection time = 1.299 ms
tps = 0.316898 (without initial connection time)
```

## Задача 4

### Задание 

[4] ускорить запрос "semi-join", добиться времени выполнения < 10sec

```sql
select day from t2 where t_id in ( select t1.id from t1 where t2.t_id = t1.id) and day > to_char(date_trunc('day',now()- '1 months'::interval),'yyyymmdd');
```

### Ответ

Дла этого запроса используем идею из предыдущего запроса.

```sql
select day from t2 where exists (select 1 from t1 where t2.t_id = t1.id) and day > to_char(date_trunc('day',now()- '1 months'::interval),'yyyymmdd');
```

После выполнения получаем результат:

```
number of transactions per client: 100
number of transactions actually processed: 100/100
number of failed transactions: 0 (0.000%)
latency average = 1808.567 ms
initial connection time = 1.510 ms
tps = 0.552924 (without initial connection time)
```