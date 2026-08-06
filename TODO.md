In the test suite:

p.43 -- the rows come out in a different order because   for x in dict   keys are in a different order
p.48, p.50 -- the pipe to "sort" spawns a process which breaks the connection between the standard output of awk and the standard output
        of the forked pipe process.  Need to rework the forking to capture the output of the subprocess
p.48b -- results of rand() don't match

t.3 -- comparison of $1 == "5" where $1 is a field like "5xxx" gets confused about whether or not to convert to int and compare or
       stick with a string comparison
t.3.x -- also problem of field numeric/string confusion   x = $1; x > 1   gives different answers


Original:
Wed Jan 22 02:10:35 MST 2020
============================

Here are some things that it'd be nice to have volunteer
help on.

1. Rework the test suite so that it's easier to maintain
and see exactly which tests fail:
	A. Extract beebe.tar into separate file and update scripts
	B. Split apart multiple tests into separate tests with input
	   and "ok" files for comparisons.

2. Pull in more of the tests from gawk that only test standard features.
   The beebe.tar file appears to be from sometime in the 1990s.

3. Make the One True Awk valgrind clean. In particular add a
   a test suite target that runs valgrind on all the tests and
   reports if there are any definite losses or any invalid reads
   or writes (similar to gawk's test of this nature).
