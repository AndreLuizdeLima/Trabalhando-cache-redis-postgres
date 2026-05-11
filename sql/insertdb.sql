DROP TABLE IF EXISTS student_courses;
DROP TABLE IF EXISTS users;

CREATE TABLE users (
	id integer PRIMARY KEY,
	nome varchar(255) NOT NULL,
	email varchar(255) NOT NULL UNIQUE
);

INSERT INTO users (id, nome, email)
SELECT 
  i,
  'Nome ' || i,
  'email' || i || '@teste.com'
FROM generate_series(1, 2000) AS i;

CREATE TABLE student_courses (
	id integer PRIMARY KEY,
	user_id integer NOT NULL REFERENCES users(id),
	course_name varchar(255) NOT NULL,
	status varchar(20) NOT NULL,
	score numeric(5, 2) NOT NULL,
	created_at timestamp NOT NULL
);

INSERT INTO student_courses (id, user_id, course_name, status, score, created_at)
SELECT
  i,
  ((random() * 1999)::integer + 1),
  'Curso ' || ((random() * 60)::integer + 1),
  CASE
    WHEN random() < 0.25 THEN 'pending'
    WHEN random() < 0.75 THEN 'active'
    ELSE 'finished'
  END,
  round((random() * 100)::numeric, 2),
  now() - (((random() * 365)::integer || ' days')::interval)
FROM generate_series(1, 150000) AS i;

CREATE INDEX idx_student_courses_user_id ON student_courses(user_id);

SELECT count(*) AS total_users FROM users;
SELECT count(*) AS total_student_courses FROM student_courses;
