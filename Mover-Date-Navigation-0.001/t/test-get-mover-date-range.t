#!/usr/bin/perl
use Modern::Perl qw/2012/;
use DateTime;
use List::Util qw/sum/;
use List::MoreUtils qw/ all any/;
use Scalar::Util qw/reftype blessed/;
use Carp qw /confess/;
use POSIX;
use Test::More;
use Test::Exception;

#use Test::Moose;
use Test::Moose::More;
use MooseX::Types::Moose qw/ HashRef /;
use Mover::Date::Types qw/MoverDateTimeHref/;

#-------------------------------------------------------------------------------
#  Test Mover::Date::Navigation get_mover_date_range
#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
# Run environment check.
#-------------------------------------------------------------------------------
diag <<EOF
*******************************WARNING*****************************
The APP_TEST environment variable is not set. Please run this test
script with the APP_TEST variable set to one e.g. APP_TEST=1 prove –l
to ensure that SmartComments and other stuff run in test only.
EOF
  if !$ENV{APP_TEST};

#------$env{app_test} is set in header script
plan skip_all => 'Set APP_TEST for the tests to run fully' if !$ENV{APP_TEST};

BEGIN {
    my $MyModule = 'Mover::Date::Navigation';
    use FindBin;

    #------Include header script
    require "$FindBin::Bin/my_test_template.pl";
    say 'Module is ' . $MyModule;

    use_ok($MyModule) || die "Bail out ! $!";

}
use_ok($MyModule) || die "Bail out ! $!";

diag("Testing $MyModule  $Mover::Date::Navigation::VERSION, Perl $], $^X");

#-------------------------------------------------------------------------------
#  Constants
#-------------------------------------------------------------------------------

use Smart::Comments -ENV;

use Readonly;

#  uses  Readonly::XS;
Readonly my $TRUE      => 1;
Readonly my $FALSE     => 0;
Readonly my $FAIL      => undef;
Readonly my $EMPTY_STR => q//;
Readonly my $EMPTY     => q/<empty>/;

#------ Mover Date Specific constants
Readonly my $UTC_TZ      => q/UTC/;
Readonly my $NEW_YORK_TZ => q{America/New_York};
Readonly my $LOCAL_TZ    => $NEW_YORK_TZ;
Readonly my $CHICAGO_TZ  => q{America/Chicago};

#------- Constraints

Readonly my $MAX_DELTA_YEARS       => 10;
Readonly my $MAX_DELTA_MONTHS      => 120;
Readonly my $MAX_DELTA_WEEKS       => 520;
Readonly my $MAX_DELTA_DAYS        => 360;
Readonly my $MAX_DELTA_HOURS       => 24;
Readonly my $MAX_DELTA_MINUTES     => 60;
Readonly my $MAX_DELTA_SECONDS     => 60;
Readonly my $MAX_DELTA_NANOSECONDS => 1000000000;

Readonly my $MIN_MOVER_YEAR => 1950;
Readonly my $MAX_MOVER_YEAR => 2100;

my $DATE_TIME_CLASS = 'DateTime';

#------ Lists
my $DATE_UNIT_REGEX =
  qr/(?<date_unit>year|month|week|day|hour|minute|second)s?/;

my $BEFORE_OR_AFTER_REGEX = qr/(?<before_or_after>before|after)/;

my $DELTA_DATE_UNIT_REGEX = qr/(?<delta_date_units>\d{1,6})/;

#------- Constraints

Readonly my %MonthToDays => (
    1  => 31,
    2  => 28,    # (Unless leap year => 29 ,)
    3  => 31,
    4  => 30,
    5  => 31,
    6  => 30,
    7  => 31,
    8  => 31,
    9  => 30,
    10 => 31,
    11 => 30,
    12 => 31,
);

#  switches between before and after. Pass current $before_or_after
#  $before_or_after = $toggle_before_or_after->(q/after/); # returns q/before/
my $toggle_before_or_after = sub { $_[0] =~ /^b/i ? q/after/ : q/before/; };

#-------------------------------------------------------------------------------
#  Subtype names
#-------------------------------------------------------------------------------

my ( $test_moose, $test_get_date_range );

#   Methods to test
#-------------------------------------------------------------------------------
#  Test Switches
#-------------------------------------------------------------------------------

my $TEST_MOOSE                = $TRUE;
my $TEST_GET_MOVER_DATE_RANGE = $TRUE;

#-------------------------------------------------------------------------------
#  Test Data
#-------------------------------------------------------------------------------

my $TestDateTime_1 = DateTime->new(
    year   => 2014,
    month  => 11,
    day    => 14,
    hour   => 06,
    minute => 15,
    second => '22'
);

my $TestDateTime_2 = DateTime->new(
    year   => 2001,
    month  => 06,
    day    => 27,
    hour   => 21,
    minute => 00,
    second => 00,
);

my $AltTestDateTime_1 = DateTime->new(
    year   => 2019,
    month  => '08',
    day    => 15,
    hour   => 10,
    minute => 30,
    second => 05,
);

my %good_test_params = (

    params_0 => {
        date_unit        => 'year',
        delta_date_units => ( $MAX_DELTA_YEARS - 1 ),
        before_or_after  => q/after/,
        base_date        => '2012-05-03T02:08:10',
        base_tz          => $LOCAL_TZ,
        expecting        => {
            year   => 2012,
            month  => 5,
            day    => 3,
            hour   => 2,
            minute => 8,
            second => 10
        },
    },
    params_1 => {
        date_unit        => 'year',
        delta_date_units => ( $MAX_DELTA_YEARS - 1 ),
        before_or_after  => q/after/,
        base_date        => undef,
        base_tz          => $LOCAL_TZ,
        expecting => undef,    # Validate against DateTime->now
    },
    params_2 => {
        date_unit        => 'month',
        delta_date_units => ( $MAX_DELTA_MONTHS - 1 ),
        before_or_after  => q/before/,
        base_date        => $TestDateTime_1,
        base_tz          => $LOCAL_TZ,
        expecting        => {
            year   => $TestDateTime_1->year(),
            month  => $TestDateTime_1->month(),
            day    => $TestDateTime_1->day(),
            hour   => $TestDateTime_1->hour(),
            minute => $TestDateTime_1->minute(),
            second => $TestDateTime_1->second(),
        },
    },
    params_3 => {
        date_unit        => 'week',
        delta_date_units => ( $MAX_DELTA_WEEKS - 1 ),
        before_or_after  => q/after/,
        base_date        => $TestDateTime_2,
        expecting        => {
            year   => $TestDateTime_2->year(),
            month  => $TestDateTime_2->month(),
            day    => $TestDateTime_2->day(),
            hour   => $TestDateTime_2->hour(),
            minute => $TestDateTime_2->minute(),
            second => $TestDateTime_2->second(),
        },

    },
    params_4 => {
        date_unit        => 'month',
        delta_date_units => ($MAX_DELTA_DAYS),
        before_or_after  => q/before/,
        base_date        => undef,
    },
    month_yyyymmdd => {
        date_unit        => 'month',
        delta_date_units => ( $MAX_DELTA_WEEKS - 1 ),
        before_or_after  => q/after/,
        base_date        => '1960/12/13',
        expecting        => {
            year   => 1960,
            month  => 12,
            day    => 13,
            hour   => 0,
            minute => 0,
            second => 0,
        },

    },
    week_spaces_yyyymmdd => {
        date_unit        => 'week',
        delta_date_units => ( $MAX_DELTA_WEEKS - 1 ),
        before_or_after  => q/after/,
        base_date        => ' 1960/12/13 ',
        expecting        => {
            year   => 1960,
            month  => 12,
            day    => 13,
            hour   => 0,
            minute => 0,
            second => 0,
        },

    },
    month_spaces_ddmmyyyy => {
        date_unit        => 'month',
        delta_date_units => ( $MAX_DELTA_WEEKS - 1 ),
        before_or_after  => q/after/,
        base_date        => ' 31/07/1965  ',
        expecting        => {
            year   => 1965,
            month  => 7,
            day    => 31,
            hour   => 0,
            minute => 0,
            second => 0,
        },

    },

    #    params_3 => {
    #        date_unit        => 'day',
    #        delta_date_units => ( $MAX_DELTA_DAYS - 1 ),
    #        before_or_after  => q/after/,
    #        base_date        => undef,
    #    },
    #    params_4 => {
    #        date_unit        => 'hour',
    #        delta_date_units => ( $MAX_DELTA_HOURS - 1 ),
    #        before_or_after  => q/after/,
    #        base_date        => undef,
    #    },
    #    params_5 => {
    #        date_unit        => 'minute',
    #        delta_date_units => ( $MAX_DELTA_MINUTES - 1 ),
    #        before_or_after  => q/after/,
    #        base_date        => undef,
    #    },
);

#------ Will only use these if I decide to make base_date a rw attribute
my %good_alt_test_params = (

    params_0 => {
        date_unit        => 'month',
        delta_date_units => ( $MAX_DELTA_MONTHS - 2 ),
        before_or_after  => q/before/,
        base_date        => '2002-06-11T12:05:35',
        base_tz          => $UTC_TZ,
        expecting        => {
            year   => 2002,
            month  => 6,
            day    => 11,
            hour   => 12,
            minute => 5,
            second => 35
        },
    },
    params_1 => {
        date_unit        => 'week',
        delta_date_units => ( $MAX_DELTA_WEEKS - 5 ),
        before_or_after  => q/before/,
        base_date        => '10-20-1972',
        base_tz          => $LOCAL_TZ,
        expecting        => {
            year   => 1972,
            month  => 10,
            day    => 20,
            hour   => 0,
            minute => 0,
            second => 0
        }
    },
    params_2 => {
        date_unit        => 'year',
        delta_date_units => ( $MAX_DELTA_YEARS - 2 ),
        before_or_after  => q/after/,
        base_date        => $TestDateTime_1,
        base_tz          => $UTC_TZ,
        expecting        => {
            year   => $AltTestDateTime_1->year(),
            month  => $AltTestDateTime_1->month(),
            day    => $AltTestDateTime_1->day(),
            hour   => $AltTestDateTime_1->hour(),
            minute => $AltTestDateTime_1->minute(),
            second => $AltTestDateTime_1->second(),
        },
    },
);

my $TestDateTimeBad_1 = DateTime->new(
    year   => 1948,
    month  => 11,
    day    => 14,
    hour   => 06,
    minute => 15,
    second => '22'
);

my $TestDateTimeBad_2 = DateTime->new(
    year   => 2101,
    month  => 06,
    day    => 27,
    hour   => 21,
    minute => 00,
    second => 00,
);

my %bad_test_params = (
    params_0 => {
        date_unit        => 'long',
        delta_date_units => q/ab/,
        before_or_after  => q/during/,
        base_date        => q/now/,
    },
#------ Having a limit on the DateTime date should be implemented 
#       at the application level,  and not int the DateTime Nav 
#       Module

#    params_1 => {
#        date_unit        => 'month',
#        delta_date_units => ($MAX_DELTA_MONTHS),
#        before_or_after  => q/after/,
#        base_date        => $TestDateTimeBad_1,
#    },
#    params_2 => {
#        date_unit        => 'week',
#        delta_date_units => ($MAX_DELTA_WEEKS),
#        before_or_after  => q/before/,
#        base_date        => $TestDateTimeBad_2,
#    },
);

#-------------------------------------------------------------------------------
#  Testing
#-------------------------------------------------------------------------------

subtest $test_moose => sub {

    plan skip_all => 'Not testing Moose now.'
      unless ($TEST_MOOSE);

    my ( $before_or_after, $range_or_single );

    use Smart::Comments -ENV;

    #------ Test Moose Attributes and roles

    diag 'Test Mover::Date::Navigation Moose stuff';

    meta_ok( 'Mover::Date::Navigation',
        'Mover::Date::Navigation class has a metaclass.' );
    does_ok(
        'Mover::Date::Navigation',
        q/Convert::Input::To::DateTime/,
        'Class has a role Convert::Input::To::DateTime.'
    );
    has_attribute_ok( 'Mover::Date::Navigation', 'date_unit',
        'Class has date_unit attribute.' );
    has_attribute_ok( 'Mover::Date::Navigation', 'delta_date_units',
        'Class has delta_date_units attribute.' );
    has_attribute_ok( 'Mover::Date::Navigation', 'before_or_after',
        'Class has before_or_after attribute.' );
    has_attribute_ok( 'Mover::Date::Navigation', 'base_date',
        'Class has base_date attribute.' );

    has_method_ok(
        'Mover::Date::Navigation',
        (
            qw/convert_to_datetime
              get_date_range/
        )
    );

};    #--- End testing of Moose stuff

#-------------------------------------------------------------------------------
#  Test get_date_range_now
#-------------------------------------------------------------------------------
subtest $test_get_date_range => sub {

    plan skip_all => 'Not testing get_date_range now.'
      unless ($TEST_GET_MOVER_DATE_RANGE);

    my ( $before_or_after, $range_or_single );

    use Smart::Comments -ENV;

    #------ Test Navigation Time Period Constraints
    #----   with Good params
    diag 'Test Good Delta time periods';
    diag '';
    for my $good_params_href ( keys %good_test_params ) {

        ##### These are the params for this Good test : $good_test_params{$good_params_href}

        #------ Year Month and Week will return an arrayref
        #      containing the first and last date of the range
        #       day, hour, minute will return an arrayref wih
        #       one element
        if ( $good_test_params{$good_params_href}->{date_unit} =~
            /year|month|week/ )
        {
            $range_or_single = 2;
        }
        else {
            $range_or_single = 1;
        }
        diag "Testing Navigation with this set of params \n"
          . convert_href_to_str( $good_test_params{$good_params_href} );

        my $MoverNav = Mover::Date::Navigation->new(
            date_unit => $good_test_params{$good_params_href}->{date_unit},
            delta_date_units =>
              $good_test_params{$good_params_href}->{delta_date_units},
            before_or_after =>
              $good_test_params{$good_params_href}->{before_or_after},
            base_date => $good_test_params{$good_params_href}->{base_date},
            base_tz   => $good_test_params{$good_params_href}->{base_tz}
              // $UTC_TZ,
        );

        #------ Test Moose Stuff
        meta_ok( $MoverNav, 'Mover::Date::Navigation object has a metaclass.' );
        does_ok( $MoverNav, q/Convert::Input::To::DateTime/,
'Mover::Date::Navigation object has a role Convert::Input::To::DateTime.'
        );
        has_attribute_ok( $MoverNav, 'date_unit',
            'Mover::Date::Navigation object has date_unit attribute.' );
        has_attribute_ok( $MoverNav, 'delta_date_units',
            'Mover::Date::Navigation object  has delta_date_units attribute.' );
        has_attribute_ok( $MoverNav, 'before_or_after',
            'Mover::Date::Navigation object  has before_or_after attribute.' );
        has_attribute_ok( $MoverNav, 'base_date',
            'Mover::Date::Navigation object  has base_date attribute.' );

        has_method_ok(
            $MoverNav,
            (
                qw/convert_to_datetime
                  get_date_range/
            )
        );

        isa_ok( $MoverNav, 'Mover::Date::Navigation',
            'Created a Date Navigation Obj.' );
        is(
            $MoverNav->date_unit,
            $good_test_params{$good_params_href}->{date_unit},
            'Valid date unit.'
        );
        is(
            $MoverNav->delta_date_units,
            $good_test_params{$good_params_href}->{delta_date_units},
            'Valid delta date units.'
        );
        is(
            $MoverNav->before_or_after,
            $good_test_params{$good_params_href}->{before_or_after},
            'Valid before_or_after string.'
        );

        #        my $BaseDate = $MoverNav->base_date;
        my $base_date_href = $MoverNav->base_date;

        #        isa_ok( $BaseDate, 'DateTime', 'Valid base date.' );
        isa_ok( $base_date_href, 'HASH', 'Valid base date.' );

        validate_attribute $MoverNav => base_date => (
            isa     => 'HASH',
            builder => '_build_base_date',
            default => undef,
            lazy    => 1,
        );

        #------ Validate the base_date, if we have expected values to validate
        #       against
        if ( defined $good_test_params{$good_params_href}->{expected} ) {

            #-----pass Our Base Date,  with expected values and message.
            is_datetime_eq_hashref(
                $MoverNav->base_date,
                $good_test_params{$good_params_href}->{expected},
                'Base date has the correct date values!'
            );
        }

        is(
            $MoverNav->base_tz,
            $good_test_params{$good_params_href}->{base_tz} // $UTC_TZ,
            'Correct base_date time zone: ' . $MoverNav->base_tz
        );

        #        is( $BaseDate->time_zone_long_name, $MoverNav->base_tz,
        #            'BaseDate time zone == MoverNav->base_tz. '
        #              . $BaseDate->time_zone_long_name );
        is( $base_date_href->{time_zone}, $MoverNav->base_tz,
            'base_date_href time zone == MoverNav->base_tz. '
              . $base_date_href->{time_zone} );
        isa_ok( $MoverNav->get_date_range(), 'ARRAY',
            'Date range is an ArrayRef!'
              . ( ref( $MoverNav->get_date_range() ) // q/Not a ref!/ ) );

        is( scalar @{ $MoverNav->get_date_range },
            $range_or_single,
            'ArrayRef has ' . $range_or_single . ' elements' );

        my ( $FirstDate, $LastDate ) = @{ $MoverNav->get_date_range };

        isa_ok( $FirstDate, 'DateTime', 'First of range is ok!' );
        if ( $range_or_single == 2 ) {

            isa_ok( $LastDate, 'DateTime', 'Last of range is ok!' );

            #----- Test if first < last
            is( DateTime->compare( $FirstDate, $LastDate ),
                -1, 'Start of range < End of range!' );

            range_ok( [ $FirstDate, $LastDate ],
                $good_test_params{$good_params_href}->{date_unit} );
        }
        else {
            ### Date Unit           : $good_test_params{$good_params_href}->{date_unit}
            ### Single DateTime mdy : $FirstDate->mdy
            ###   with hms          : $FirstDate->hms
        }

        my $old_before_or_after = $MoverNav->before_or_after;
        diag ' Toggle before_or_after from '
          . $old_before_or_after
          . ' and test.';
        my $before_or_after =
          $toggle_before_or_after->( $MoverNav->before_or_after );

        $MoverNav->before_or_after($before_or_after);
        is( $MoverNav->before_or_after(),
            $before_or_after, 'Set before_or_after to ' . $before_or_after );

        #        dies_ok( sub { $MoverNav->base_date( DateTime->now ) },
        #            'Not allowed to change base_date!' );
        diag 'Change base_tz to ' . $CHICAGO_TZ;
        $MoverNav->base_tz($CHICAGO_TZ);

#        is( $MoverNav->base_date()->time_zone_long_name, $CHICAGO_TZ,
#                $BaseDate->time_zone_long_name
#              . ' the base_date time zone is changed when base_tz is changed to '
#              . $CHICAGO_TZ );
        is( $MoverNav->base_date()->{time_zone}, $CHICAGO_TZ,
                $base_date_href->{time_zone}
              . ' the base_date time zone is changed when base_tz is changed to '
              . $CHICAGO_TZ );

    }

    #---- Bad params
    diag 'Testing get_date_range.';
    diag ' with Bad Input Parameters';
    for my $bad_params_href ( keys %bad_test_params ) {

        dies_ok(
            sub {
                Mover::Date::Navigation->new(
                    $bad_test_params{$bad_params_href},
                );
            },
            'Bad parameters cause a death!' . "\n"
              . convert_href_to_str( $bad_test_params{$bad_params_href} )
        );
    }

};    # End testing get_date_range_now

#-------------------------------------------------------------------------------
#  Useful Subs
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#  Test to see if Date Range is the required length.
#-------------------------------------------------------------------------------
sub range_ok {
    confess(
        'Need to send an ArrayRef of Dates to range_ok
        test!'
    ) unless ( ( $_[0] ) && ( ref( $_[0] ) eq 'ARRAY' ) );
    confess('Need to send a valid date_unit to range_ok test!')
      unless ( ( $_[1] ) && ( $_[1] =~ /^$DATE_UNIT_REGEX$/ ) );
    my ( $got_duration, $got_total_range );

    my ( $got_aref, $date_unit, $test_desc ) = @_;
    my $GotFirst = shift @$got_aref;
    my $GotLast  = shift @$got_aref;
    $GotFirst->set_time_zone($UTC_TZ);
    $GotLast->set_time_zone($UTC_TZ);

    #---- get the actual range duration in days
    $got_duration = $GotFirst->delta_days($GotLast);
    my %duration_h = $got_duration->deltas;
    $got_total_range = $duration_h{days};

    my %expect_date_unit_range = (
        year  => days_in_year($GotFirst) - 1,
        month => days_in_month($GotFirst) - 1,
        week  => 6,                              # days
    );

    $test_desc //= ( 'Date range is one ' . $date_unit . ' apart!' );

    is( $got_total_range, $expect_date_unit_range{$date_unit}, $test_desc )
      or ('Got a date range of duation '
        . $got_total_range
        . ' which should be  '
        . $expect_date_unit_range{$date_unit}
        . $date_unit
        . 's apart!' );

}

#-------------------------------------------------------------------------------
#  Pass actual result,  ArayRef of expected results and test name.
#-------------------------------------------------------------------------------
sub is_any {

    my ( $actual, $expected, $name ) = @_;

    $name ||= '';

    ok( ( any { $_ eq $actual } @$expected ), $name )

      or diag "Received: $actual\nExpected:\n" .

      join "", map { "         $_\n" } @$expected;

}

#-------------------------------------------------------------------------------
#  Get the number of days in a month
#  Pass a DateTime
#-------------------------------------------------------------------------------
sub days_in_month {
    my $DateTime = shift;
    confess('Need to send a DateTime!')
      unless ( $DateTime
        && $DateTime->isa('DateTime') );

    my $number_of_days = $MonthToDays{ $DateTime->month };

    if ( ( $DateTime->month == 2 ) && ( $DateTime->is_leap_year ) ) {
        $number_of_days = 29;
    }

    return $number_of_days;
}

#-------------------------------------------------------------------------------
#  Compare a Got: DateTime with an Expected: HashRef
#-------------------------------------------------------------------------------
sub is_datetime_eq_hashref {
    my ( $GotDt, $expected_href, $info_msg ) = @_;
    confess('Must send an expected HashRef!')
      unless ( ref($expected_href) eq 'HASH' );
    ### Testing a 'Got' DateTime with an expected HashRef
    my $what_d_we_get =
      $GotDt
      ? (
        ( blessed($GotDt) eq 'DateTime' )
        ? 'YMD from DateTime Obj: ' . $GotDt->ymd()
        : 'This isnt a DateTime ' . $GotDt
      )
      : q/Got Nothing!/;
    ### 'Got' DateTime : $what_d_we_get

    $info_msg //= 'DateTime data corresponds to HashRef data.';
    $GotDt //= fail($info_msg);
    if ( not blessed($GotDt) eq 'DateTime' ) {
        fail($info_msg);
        diag 'Received: '
          . ( $GotDt // q/No DateTime Object/ )
          . "\nExpected:\n"
          . join "", map { "         $_\n" } keys %$expected_href;
        return $FAIL;
    }
    my $got_href;

    #--- Populate Got Hash with data from GotDt
    $got_href->{year}   = $GotDt->year()   // 0;
    $got_href->{month}  = $GotDt->month()  // 0;
    $got_href->{day}    = $GotDt->day()    // 0;
    $got_href->{hour}   = $GotDt->hour()   // 0;
    $got_href->{minute} = $GotDt->minute() // 0;
    $got_href->{second} = $GotDt->second() // 0;

    diag "\nGot(stringified Hash ) "
      . convert_datetime_href_to_str($got_href)
      . ' expected '
      . convert_datetime_href_to_str($expected_href);

    is_deeply( $got_href, $expected_href, $info_msg );

}

#-------------------------------------------------------------------------------
#  Get the number of days in a year
#  Pass a DateTime
#-------------------------------------------------------------------------------
sub days_in_year {
    my $DateTime = shift;
    confess('Need to send a DateTime!')
      unless ( $DateTime
        && $DateTime->isa('DateTime') );

    return ( $DateTime->is_leap_year ) ? 366 : 365;
}

#-------------------------------------------------------------------------------
#  Convert HashRef to String
#  Converts Key Value pairs to a string % key : value % key : value % ....
#  Converts DateTime Value to string also.
#-------------------------------------------------------------------------------
sub convert_href_to_str {
    my $href = shift;
    return fail('Must send a HashRef to convert_href_to_str !')
      unless ( ref($href) eq 'HASH' );
    my $hash_as_str = q//;
    for my $key ( keys %$href ) {
        $hash_as_str .= ', ' if length($hash_as_str);
        my $value;
        if ( $href->{$key} and blessed( $href->{$key} eq 'DateTime' ) ) {
            $value = 'From DateTime Object: '
              . convert_datetime_to_str( $href->{$key} );
        }
        else {
            $value = $href->{$key};
        }
        $hash_as_str .= $key . ' : ' . ( $value // $EMPTY );
    }
    return $hash_as_str;
}

#-------------------------------------------------------------------------------
#  Convert DateTime HashRef to String
#-------------------------------------------------------------------------------
sub convert_datetime_href_to_str {
    my $href = shift;
    return fail('Must send a HashRef to convert_datetime_href_to_str !')
      unless ( ref($href) eq 'HASH' );
    return
        ( $href->{year}   // '00' ) . '/'
      . ( $href->{month}  // '00' ) . '/'
      . ( $href->{day}    // '00' ) . ' T '
      . ( $href->{hour}   // '00' ) . ':'
      . ( $href->{minute} // '00' ) . ':'
      . ( $href->{second} // '00' );
}

#-------------------------------------------------------------------------------
#  Convert DateTime to String
#-------------------------------------------------------------------------------
sub convert_datetime_to_str {
    my $Dt = shift;
    return fail('Must send a DateTime so it can be converted to a string!')
      unless ( blessed($Dt) eq 'DateTime' );
    return
        ( $Dt->year   // '00' ) . '/'
      . ( $Dt->month  // '00' ) . '/'
      . ( $Dt->day    // '00' ) . ' T '
      . ( $Dt->hour   // '00' ) . ':'
      . ( $Dt->minute // '00' ) . ':'
      . ( $Dt->second // '00' );
}

#-------------------------------------------------------------------------------
#  Temporary end marker
#-------------------------------------------------------------------------------
done_testing();
__END__
