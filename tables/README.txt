
Example how to list all tables in gitlab database:

gitlab-psql --dbname=gitlabhq_production --command='\dt' | tee gitlab-AA-X.Y.Z-tables.txt

