create table users (
	id integer,
	nome varchar(255),
	email varchar(255)
)

INSERT INTO users (id, nome, email)
SELECT 
  i,
  'Nome ' || i,
  'email' || i || '@teste.com'
FROM generate_series(1, 2000) AS i;

select count(*) from users