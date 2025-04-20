select day from t2 where not exists (select 1 from t1 where t1.id = t2.t_id);
