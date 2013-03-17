#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Mover::Date::Navigation' ) || print "Bail out!\n";
}

diag( "Testing Mover::Date::Navigation $Mover::Date::Navigation::VERSION, Perl $], $^X" );
