-- The routines you write in the database.
--
-- Write them in pgAdmin against the university database, test them there,
-- and then call them from TypeScript. Fill in the parts marked TODO.
--
-- You already have one routine in this database: danish_grade(letter), from
-- Task 5 of the database exercises. Both parts of this assignment use it, so
-- check that it is still there before you start:
--
--     SELECT danish_grade('A'), danish_grade('C-'), danish_grade(NULL);
--
-- If it is gone, the exercises folder has the file you wrote it in.


-- B2. A FUNCTION that queries and returns a result set.
--
-- student_transcript(p_id) returns one row per course the student takes,
-- with the course id, the title, and the grade **already converted** by
-- danish_grade. Order by course id.
--
-- Unlike danish_grade, this one reads tables and needs control flow, so it
-- is written in plpgsql. It must raise an exception when the student does
-- not exist:
--
--     RAISE EXCEPTION 'No student with id %', p_id;
--
-- A trap: CREATE OR REPLACE FUNCTION fails once you change which columns it
-- returns. The message tells you to drop it first:
--
--     DROP FUNCTION student_transcript(varchar);

CREATE OR REPLACE FUNCTION student_transcript(p_id varchar)
RETURNS TABLE (course_id varchar, title varchar, grade varchar)
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM student s WHERE s.id = p_id) THEN
    RAISE EXCEPTION 'No student with id %', p_id;
  END IF;

  RETURN QUERY
    SELECT t.course_id,
            c.title,
            danish_grade(t.grade)::varchar
    FROM takes t
    JOIN course c ON c.course_id = t.course_id
    WHERE t.id = p_id
    ORDER BY t.course_id;
  RETURN;
END;
$$;

-- Test it:
--     SELECT * FROM student_transcript('00128');   -- two rows, grades 12 and 10
--     SELECT * FROM student_transcript('99999');   -- an error


-- B3. A PROCEDURE that changes several things.
--
-- enrol_student must:
--   look up the credits of the course, and raise an exception when the
--     course does not exist
--   insert a row into takes, with a null grade
--   add the course credits to the student's tot_cred
--   report the student's new total through the INOUT parameter
--
-- A procedure, not a function, because it exists to change things rather
-- than to answer a question.

CREATE OR REPLACE PROCEDURE enrol_student(
  p_id varchar,
  p_course_id varchar,
  p_sec_id varchar,
  p_semester varchar,
  p_year numeric,
  INOUT new_total numeric DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
  v_credits numeric;
BEGIN
  -- 1. Look up the credits, an unknown course is an error.
  SELECT credits INTO v_credits
    FROM course
    WHERE course_id = p_course_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No course with id %', p_course_id;
  END IF;

  -- 2. The enrolment where grade is left out, so it becomes NULL.
  INSERT INTO takes (id, course_id, sec_id, semester, year)
  VALUES (p_id, p_course_id, p_sec_id, p_semester, p_year);

  -- 3. The credits, and the new total
  UPDATE student
    SET tot_cred = tot_cred + v_credits
    WHERE id = p_id
  RETURNING tot_cred INTO new_total;
END;
$$;

-- Test it:
--     CALL enrol_student('70557', 'CS-319', '1', 'Spring', 2018);

-- ## B3: TypeScript vs. a stored procedure

-- B1 keeps the rule in one language with the rest of the code, where it is
-- easy to test and change, but we have to manage the transaction ourselves,
-- and the rule only holds for code that goes through our function. B3 is
-- atomic by itself and enforces the rule for every client of the database,
-- but splits the logic across two languages and is harder to test and change. 
-- We would keep business logic in TypeScript for maintainability, and leave 
-- the database to enforce what must always hold such as keys and constraints. 
-- The cost of that choice is that nothing stops inconsistent data if someone 
-- writes to the database without going through the application.