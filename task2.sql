select day from t2 where t_id in (select id from t1 where name like 'a%') order by day DESC LIMIT 1;
