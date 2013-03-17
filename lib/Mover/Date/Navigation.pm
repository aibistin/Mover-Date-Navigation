# ABSTRACT: Mover Date Navigation 
package Mover::Date::Navigation;
use Modern::Perl q/2012/;
use autodie;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;

=head2
 Include role Convert::Input::To::DateTime to convert input
 in any format to a DateTime date object.
=cut

with 'Convert::Input::To::DateTime';

our $VERSION = q/0.001/;    # from D Golden blog
$VERSION = eval $VERSION;

use Mover::Date::Types qw /
  MoverDateTime
  MoverDateTimeRecent
  MoverDateUnit
  MoverBeforeOrAfter
  MoverDateHref
  MoverDateTimeHref
  MoverDateTimeStrIso
  /;

use Scalar::Util qw/tainted blessed looks_like_number/;
use String::Util qw/trim hascontent/;
use Log::Any qw/$log/;
use Try::Tiny;
use MooseX::Types::Moose qw/ ArrayRef /;
use MooseX::Types::Common::Numeric qw/PositiveOrZeroInt/;
use MooseX::Types::Common::String qw/NonEmptyStr/;

#-------------------------------------------------------------------------------
#  Constants
#-------------------------------------------------------------------------------
use Readonly;

Readonly my $EMPTY_STR => q//;

#------ Mover Date Specific constants
Readonly my $UTC_TZ                   => 'UTC';
Readonly my $NEW_YORK_TZ              => 'America/New_York';
Readonly my $LOCAL_TZ                 => $NEW_YORK_TZ;
Readonly my $BEFORE_BASE_DATE         => q/before/;
Readonly my $AFTER_BASE_DATE          => q/after/;
Readonly my $DATE_TIME_OBJ            => q/DateTime/;
Readonly my $MOVER_DATE_TIME_OBJ      => q/MoverDateTime/;
Readonly my $MOVER_DATE_TIME_HREF_OBJ => q/MoverDateTimeHref/;

Readonly my $MIN_MOVER_YEAR => 1950;
Readonly my $MAX_MOVER_YEAR => 2100;

#------  Number to Month
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

#---- Helper private subroutines
my (
    $is_datetime_obj,
    $is_datetime_obj_or_confess,
    $str_has_untainted_content_or_confess,
    $hashref_has_untainted_content_or_confess,
    $get_untainted_trimmed_hash_from_hash_or_hashref
);

#-------------------------------------------------------------------------------
#                   Attributes
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#  Date Navigation Constraint Attrbutes
#-------------------------------------------------------------------------------

#------ Date Units are  year, month, week, day, hour, minute

=head2 date_unit
 String to represent date units,  year, month, week, day, hour, minute.
 Is a 'rw' attribute.
=cut

has 'date_unit' =>
  ( is => 'rw', isa => MoverDateUnit, coerce => 1, required => 1 );

=head2 delta_date_units
 Number of days before or after a specific base date
 Defaults to 0.
 Is a 'rw' attribute.

=cut

has 'delta_date_units' =>
  ( is => 'rw', isa => PositiveOrZeroInt, default => 0 );

=head2 before_or_after
 String to represent before_or_after a particular date.
 q/before/ or q/after/.
 Defaults to q/after/.
 Is a 'rw' attribute.

=cut

has 'before_or_after' => (
    is      => 'rw',
    isa     => MoverBeforeOrAfter,
    coerce  => 1,
    default => $AFTER_BASE_DATE
);

=head2 base_date
 Starting point for the date navigation.
 MoverDateTimeHref object. 
 Uses role Convert::Input::To::DateTime to convert input to a DateTime
 object which is then converted to a DateTime hashref..
 It will accept and coerce a date in String, HashRef or DateTime format.
 This is a 'rw' attribute.

=cut

#------ No coersion to be used for this attribute as the role
#       Convert::Input::To::DateTime does a better job of 'to' DateTime
#       conversion

has 'base_date' => (
    is       => 'rw',
    required => 1,
    isa      => MoverDateTimeHref,
    lazy     => 1,
    builder  => '_build_base_date',
    trigger  => \&_base_date_trigger,
);

=head2 base_tz
 The time zone for the base_date.
 Defaults to 'UTC'
 Is a 'rw' attribute.

=cut

has 'base_tz' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => $UTC_TZ,
    trigger => \&_base_tz_trigger,
);

#-------------------------------------------------------------------------------
#  Bob the Builders
#-------------------------------------------------------------------------------
around 'BUILDARGS' => sub {
    my $orig  = shift;
    my $class = shift;

    #------ Taint check, trim value strings and return a Hash, even if passed
    #       hashref.
    my %clean_hash = $get_untainted_trimmed_hash_from_hash_or_hashref->(@_);
    my $BaseDt;

    #--- Convert the Input Base Date to a DateTime Object.
    #    Use DateTime now if no base_date is passed.
    if ( defined $clean_hash{base_date} && length $clean_hash{base_date} ) {
        $BaseDt = $class->convert_to_datetime( $clean_hash{base_date} );
    }
    else {
        $BaseDt = DateTime->now;
    }

    #----- Converting to DateTime first, then converting to a DateTime
    #      HashRef   - May use DateTime::Tiny in next release to reduce
    #      this overhead.
    if ( ( defined $BaseDt ) and ( blessed($BaseDt) eq 'DateTime' ) ) {
        $clean_hash{base_date} = to_MoverDateTimeHref($BaseDt);
    }
    else {
        ### Buildargs couldnt convert to a DateTime from : $clean_hash{base_date}
        $log->error( 'Buildargs couldnt convert to a DateTime from '
              . $clean_hash{base_date} );
        confess('Unable to recognize the base_date attribute!');
    }
    return $class->$orig(%clean_hash);
};

#------ Add the finishing touches to this Object.
sub BUILD {
    my $self = shift;
    $self->base_date()->{time_zone} = $self->base_tz;
}

sub _build_base_date {

    #--- Create a MoverDateTimeHref from DateTime for less memory hogging.
    #    Using DateTime bacause at least I know it is cross platform
    #    compatible
    return to_MoverDateTimeHref( DateTime->now() );
}

#-------------------------------------------------------------------------------
#  Method Modifiers
#-------------------------------------------------------------------------------
#------ Convert any passed date format to MoverDateTimeHref
around q/base_date/ => sub {
    my $orig = shift;
    my $self = shift;
    if ( $_[0] ) {
        return $self->$orig(
            to_MoverDateTimeHref( $self->convert_to_datetime( $_[0] ) ) );
    }

    #--- just accessing.
    return $self->$orig();
};

#-------------------------------------------------------------------------------
#  Triggers
#-------------------------------------------------------------------------------

#------ If the base_tz is changed, so should the base_date time zone
sub _base_tz_trigger {
    my ( $self, $new_base_tz, $old_base_tz ) = @_;
    if ($old_base_tz) {
        $self->base_date()->{time_zone} = $new_base_tz;
    }
}

#------ If the base_date is changed, its time zone should be changed also
sub _base_date_trigger {
    my ( $self, $new_base_date, $old_base_date ) = @_;
    $new_base_date->{time_zone} = $self->base_tz;
}

###############################################################################
#                            DATE NAVIGATION
###############################################################################

#-------------------------------------------------------------------------------
#  Day Navigation
#-------------------------------------------------------------------------------

=head2 get_now_dt
 Create a DateTime object with time zone set to the base time zone.
 my $MoverNowDt = $MoverDate->get_now_dt();

=cut

sub get_now_dt {
    my $self = shift;
    return DateTime->now( time_zone => $self->base_tz() );
}

#-------------------------------------------------------------------------------
#  Get Delta DateTime
#-------------------------------------------------------------------------------

=head2 get_delta_datetime
 Returns a DateTime Object which is delta_date_units before_or_after
 a given base_date or DateTime->now().
 Assumes that all the required Mover::Date::Navigation Attributes are 
 properly set. (Maybe thats too big of an assumption.)

 my $FutureDate = $MoverNav->get_delta_datetime();
 
=cut      

sub get_delta_datetime {
    my $self = shift;
    return $self->_get_delta_dt_from_base();
}

#-------------------------------------------------------------------------------
#  Get Date Range
#-------------------------------------------------------------------------------

=head2 get_date_range
 Returns an array ref of two DateTime objects, one for the start and one
 end of the requested date_period(year, month, week).
 For day, hour or minute, only one truncated DateTime object will be
 included in the returned ArrayRef.

 my $date_range_arr =  $MoverDateNav->get_date_range();
=cut      

sub get_date_range {
    my $self = shift;
    return $self->_get_date_range_dispatcher();
}

=head2 get_previous_and_next_date_range_params
 Having got the relevant date range, now set up the parameters for the date range
 before and after the current date range. 
 This will make it easier for the requesting application to create links to the previous
 and next time periods.
 Returns an array with two hash refs (\%prev_params, \%next_params).
 my @prev_and_next_params = $MoverDate->get_previous_and_next_date_range_params(); 

=cut

sub get_previous_and_next_date_range_params {
    my $self = shift;
    my $prev_params;
    my $next_params;

    #--- starting from the current base_date position.
    if ( $self->delta_date_units == 0 ) {
        $prev_params = {
            date_unit        => $self->date_unit(),
            delta_date_units => 1,
            before_or_after  => $BEFORE_BASE_DATE,
        };
        $next_params = {
            date_unit        => $self->date_unit(),
            delta_date_units => 1,
            before_or_after  => $AFTER_BASE_DATE,
        };
    }
    elsif ( $self->before_or_after() eq $BEFORE_BASE_DATE ) {

        #--- Current position is prior to the base_date
        $prev_params = {
            date_unit        => $self->date_unit(),
            delta_date_units => ( $self->delta_date_units() + 1 ),
            before_or_after  => $BEFORE_BASE_DATE,
        };
        $next_params = {
            date_unit        => $self->date_unit(),
            delta_date_units => ( $self->delta_date_units() - 1 ),
            before_or_after  => $BEFORE_BASE_DATE,
        };
    }
    else {

        #--- Current position is after the base_date
        $prev_params = {
            date_unit        => $self->date_unit(),
            delta_date_units => ( $self->delta_date_units() - 1 ),
            before_or_after  => $AFTER_BASE_DATE,
        };
        $next_params = {
            date_unit        => $self->date_unit(),
            delta_date_units => ( $self->delta_date_units() + 1 ),
            before_or_after  => $AFTER_BASE_DATE,
        };
    }
    $log->debug(
        'Got previous and next date period params for
        ' . $self->date_unit()
    );
    return ( $prev_params, $next_params );
}

#-------------------------------------------------------------------------------
#           PRIVATE METHODS
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#   Method Modifiers
#-------------------------------------------------------------------------------

=head2 around qw/ get_date_range get_delta_datetime /
 Validate the calling parameters of these date navigation methods.
 If the BaseDate is in DateTime format, use the cloned DateTime version.
 If the BaseDate is not in DateTime format, then convert from whatever date
 format to DateTime or else get DateTime now.
=cut

for my $sub (qw/ get_date_range get_delta_datetime /) {
    around $sub => sub {
        my $orig = shift;
        my $self = shift;
        confess(
            $orig . ' must be invoked as a Mover::Date::Navigation method.' )
          unless ( ( defined $self )
            and ( blessed $self)
            and ( $self->isa('Mover::Date::Navigation') ) );
        return $self->$orig();
      }
}

#-------------------------------------------------------------------------------
#                   Private Navigation Methods
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#  Get the Start and End DateTimes
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# _get_delta_datetime
# Create a DateTime object with time zone to represent a date,  delta
# date_units before or after a given Base DateTime.
# Valid Mover Date units are year, month, week, day, hour or minute.
# If no base $DateTime is passed, the default is DateTime->now(time_zone => $self->base_tz()).
# The returned DateTime is in the base_tz.
#
# my $DateTime =  $MoverDateNav->_get_delta_datetime();
# The returned DateTime object is truncated to the date_unit value.
# (So, if date_unit is year, the returned DateTime is truncated to year.)
#
#-------------------------------------------------------------------------------

sub _get_delta_datetime {
    my $self = shift;
    return $self->_get_delta_dt_from_base();
}

#-------------------------------------------------------------------------------
#  _get_date_range_dispatcher
#    Returns an array ref of two DateTime objects, one for the start and one
#    end of the date_period.
#    For day, hour or minute, only one truncated DateTime object will be
#    included within the returned ArrayRef.
#
#    my $date_range_arr =  $MoverDateNav->get_date_range();
#
#-------------------------------------------------------------------------------

sub _get_date_range_dispatcher {
    my $self = shift;

    #------ First get the DateTime delta_date_units from
    #       the base_date truncated to the current date_unit
    my $DeltaDt   = $self->_get_delta_dt_from_base();
    my $date_unit = $self->date_unit();
    my $date_range;
  SWITCH: {

        #----- Year range
        ( $date_unit eq 'year' ) && do {
            $date_range = $self->_get_first_and_last_day_of_year($DeltaDt);
            last SWITCH;
        };

        #----- Month range
        ( $date_unit eq 'month' ) && do {
            $date_range = $self->_get_first_and_last_day_of_month($DeltaDt);
            last SWITCH;
        };

        #----- Week range
        ( $date_unit eq 'week' ) && do {
            $date_range = $self->_get_first_and_last_day_of_week($DeltaDt);
            last SWITCH;
        };

        #----- Day range
        ( $date_unit eq 'day' ) && do {
            $date_range = [$DeltaDt];
            last SWITCH;
        };

        #----- Default date_unit is Hour, Minute or Second
        #      DeltaDt is already truncated to the specified date_unit
        $log->debug( 'Got date range, with one date! ' . ( $DeltaDt . "" ) );
        last SWITCH;
    }
    $log->debug(
        'Got date range, with two dates! ' . join( ', ', @$date_range ) )
      if $date_range;
    return $date_range // [$DeltaDt];
}

#-------------------------------------------------------------------------------
#  Delta Generic Time Units
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# _get_delta_dt_from_base
# Get DateTime that is delta units from given base DateTime
# If the date unit is a time period (year, month, week)
# the returned DateTime will be truncated to the first day of that period
# (Monday for week).
# If the date unit is a (day, hour)
# the returned DateTime will be truncated to the first hour of the day or the
# first minute of the hour.
#-------------------------------------------------------------------------------

sub _get_delta_dt_from_base {
    my $self = shift;

    #----- Convert from HashRef to DateTime
    my $StartDateTime = to_MoverDateTime( $self->base_date() );
    my $tz_save       = $StartDateTime->time_zone();

    $StartDateTime->set_time_zone($UTC_TZ);
    my $date_units      = $self->date_unit() . 's';
    my $add_or_subtract = $self->_add_or_subtract();

    #------  DateTime->add('month' => 5)->truncate(to => 'month')
    return $StartDateTime->$add_or_subtract(
        $date_units => $self->delta_date_units() )->set_time_zone($tz_save)
      ->truncate( to => $self->date_unit() );
}

#-------------------------------------------------------------------------------
# _add_or_subtract
#  Converts before_or_after to add or subtract.
#  Returns:
#  before_or_after == q/after/   # add
#  before_or_after == q/before/  # subtract
#-------------------------------------------------------------------------------
sub _add_or_subtract {
    return ( $_[0]->before_or_after() eq $BEFORE_BASE_DATE )
      ? q/subtract/
      : q/add/;
}

#-------------------------------------------------------------------------------
#  Today
#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
# _get_mover_today
# Returns a DatTime Object in the correct time zone truncated to day.
#-------------------------------------------------------------------------------
sub _get_mover_today {
    my $self = shift;
    return DateTime->now( time_zone => $self->base_tz() )
      ->truncate( to => 'day' );
}

#-------------------------------------------------------------------------------
#  Weeks
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#  _get_first_day_of_week
# Pass DateTime object to establish which week, otherwise it will default to
# the current week.
# Returns DateTime Object to represent Monday.
#-------------------------------------------------------------------------------
sub _get_first_day_of_week {
    my $self = shift;

    my $BaseDt = shift // $self->_get_mover_today();
    return $BaseDt->truncate( to => 'week' );
}

#-------------------------------------------------------------------------------
#  _get_last_day_of_week
# Pass DateTime object to establish which week, otherwise it will default to
# the current week.
# Returns DateTime Object to represent Sunday.
#
#-------------------------------------------------------------------------------

sub _get_last_day_of_week {
    my $self = shift;
    my $BaseDt = shift // $self->_get_mover_today();
    $BaseDt->truncate( to => 'week' );
    return $BaseDt->add( days => 6 );
}

#-------------------------------------------------------------------------------
#  _get_first_and_last_day_of_week
# Pass a DateTime Object to establish wich week, or it will default to the
# current week.
# Returns ArayRef with start of week DateTime (Monday) and end of week DateTime
# (Sunday).
# [$DateTimeFirstDay, $DateTimeLstDay] = $self->_get_first_and_last_day_of_week->($BaseDateTime);
#-------------------------------------------------------------------------------

sub _get_first_and_last_day_of_week {
    my $self     = shift;
    my $BaseDt   = $is_datetime_obj_or_confess->(shift);
    my $FirstDay = $self->_get_first_day_of_week( $BaseDt->clone() );
    my $LastDay  = $self->_get_last_day_of_week( $FirstDay->clone() );
    return [ $FirstDay, $LastDay ];
}

#-------------------------------------------------------------------------------
#  Months
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#  _get_first_day_of_month
# Pass DateTime object to establish which month, otherwise it will default to
# the current month.
# Returns DateTime Object to represent the months first day.
#-------------------------------------------------------------------------------

sub _get_first_day_of_month {
    my $self   = shift;
    my $BaseDt = $is_datetime_obj_or_confess->(shift);
    return $BaseDt->set_day(1);
}

#-------------------------------------------------------------------------------
#  _get_last_day_of_month
# Pass DateTime object to establish which month, otherwise it will default to
# the current month.
# Returns DateTime Object to represent the months final day.
#-------------------------------------------------------------------------------

sub _get_last_day_of_month {
    my $self = shift;
    my $BaseDt = shift // $self->_get_mover_today();

    #Convert month number to # of days for that month.
    my $month_days = $MonthToDays{ $BaseDt->month };
    if ( ( $month_days == '28' ) && ( $BaseDt->is_leap_year() ) ) {
        $month_days = 29;
    }

    return $BaseDt->set( day => $month_days );
}

#-------------------------------------------------------------------------------
#  _get_first_and_last_day_of_month
# Pass a DateTime Object to establish which month, or it will default to the
# current month.
# Returns ArayRef with start of month DateTime and end of month DateTime.
#
# [$DateTimeFirstDay, $DateTimeLstDay] =
#         $self->_get_first_and_last_day_of_month->($BaseDateTime);
#-------------------------------------------------------------------------------

sub _get_first_and_last_day_of_month {
    my $self     = shift;
    my $BaseDt   = $is_datetime_obj_or_confess->(shift);
    my $FirstDay = $self->_get_first_day_of_month( $BaseDt->clone() );
    my $LastDay  = $self->_get_last_day_of_month( $FirstDay->clone() );
    return [ $FirstDay, $LastDay ];
}

#-------------------------------------------------------------------------------
#   Years
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#  _get_first_day_of_year
# Pass DateTime object to establish which year, otherwise it will default to
# the current year.
# Returns DateTime Object to represent the years first day.
#-------------------------------------------------------------------------------

sub _get_first_day_of_year {
    my $self = shift;
    my $BaseDt = shift // $self->_get_mover_today();
    return $BaseDt->set( month => 1, day => 1 );
}

#-------------------------------------------------------------------------------
#  _get_last_day_of_year
# Pass DateTime object to establish which year, otherwise it will default to
# the current year.
# Returns DateTime Object to represent the years final day.
#-------------------------------------------------------------------------------

sub _get_last_day_of_year {
    my $self   = shift;
    my $BaseDt = $is_datetime_obj_or_confess->(shift);

    return DateTime->new(
        year      => $BaseDt->year(),
        month     => 12,
        day       => 31,
        hour      => $BaseDt->hour(),
        minute    => $BaseDt->minute(),
        time_zone => $BaseDt->time_zone(),
    );

}

#-------------------------------------------------------------------------------
#  _get_first_and_last_day_of_year
# Pass a DateTime Object to establish which year, or it will default to the
# current year.
# Returns ArayRef with start of year DateTime and end of month DateTime.
#
# [$DateTimeFirstDay, $DateTimeLstDay] =
#         $self->_get_first_and_last_day_of_year->($BaseDateTime);
#-------------------------------------------------------------------------------

sub _get_first_and_last_day_of_year {
    my $self     = shift;
    my $BaseDt   = $is_datetime_obj_or_confess->(shift);
    my $FirstDay = $self->_get_first_day_of_year( $BaseDt->clone() );
    my $LastDay  = $self->_get_last_day_of_year( $FirstDay->clone() );
    return [ $FirstDay, $LastDay ];
}

#-------------------------------------------------------------------------------
#  Generic Helper Subroutines
#  Mainly for error handling.
#-------------------------------------------------------------------------------

$is_datetime_obj = sub {
    return $_[0] if ( ( defined $_[0] ) && ( $_[0]->isa('DateTime') ) );
};

$is_datetime_obj_or_confess = sub {
    confess( ( $_[0] // $EMPTY_STR ) . ' is not a DateTime object. ' )
      unless ( ( defined $_[0] ) && ( $_[0]->isa('DateTime') ) );
    return $_[0];
};

$str_has_untainted_content_or_confess = sub {
    confess('Empty or tainted date string passed to Mover::Date!')
      unless ( ( hascontent $_[0] )
        && ( not tainted $_[0] ) );
    return $_[0];
};

#-------------------------------------------------------------------------------
# Examine HashRef to make sure it is a HashRef and that it or none of
# its values are tainted.
#-------------------------------------------------------------------------------
$hashref_has_untainted_content_or_confess = sub {
    confess(
        'Either the params are not in HashRef format or they contain
        tainted data!'
    ) if ( ( tainted $_[0] ) or ( ref( $_[0] ) ne 'HASH' ) );
    my $hash_ref = shift;
    my %clean_hash;

    foreach my $key ( keys %$hash_ref ) {

        confess('Tainted hashref key sent to Mover::Date::Navigation!')
          if ( tainted $key);
        confess('Tainted hashref value sent to Mover::Date::Navigation!')
          if ( tainted $hash_ref->{$key} );
        $clean_hash{ trim($key) } = trim( $hash_ref->{$key} );

    }
    return \%clean_hash;
};

#-------------------------------------------------------------------------------
# Examine a Hash or a HashRef to make sure it is a Hash and that it or none of
# its values are tainted.
# Returns a Hash even if a HashRef is sent.
#-------------------------------------------------------------------------------
$get_untainted_trimmed_hash_from_hash_or_hashref = sub {
    confess('Sent tainted data to get_untainted_trimmed_hash!')
      if ( tainted $_[0] );

    my (%hash) = ( ref $_[0] eq 'HASH' ) ? %{ $_[0] } : @_;

    my %clean_hash;

    foreach my $key ( keys %hash ) {

        confess('Tainted hash key sent to Mover::Date::Navigation!')
          if ( tainted $key);
        confess('Tainted hash value sent to Mover::Date::Navigation!')
          if ( tainted $hash{$key} );
        $clean_hash{ trim($key) } = trim( $hash{$key} );
    }
    return %clean_hash;
};

#-------------------------------------------------------------------------------
#  END
#-------------------------------------------------------------------------------
no Moose;
__PACKAGE__->meta->make_immutable;
1;    # End of Mover::Date::Navigation
__END__


=head1 NAME

Mover::Date::Navigation - Moose Object For Traversing Across Dates And Times

=head1 DESCRIPTION
 Used to get dates, date ranges in the future or past, relative to a given
 base date.


=head1 AUTHOR

austin,,,


=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

 use Mover::Date::Navigation;  # To traverse across Movers Dates and Times

 The the attributes can be sent as named paramaters or as a single HashRef
 with all the elements.

 my $MoverDateNav = Mover::Date::Navigation->new(
    date_unit        => $date_unit,  # year|month|week|day|hour|minute
    delta_date_units => $int,        # Number of $date_unit's from base_date
    before_or_after  => $before_or_after,  # q/after|before/
    base_date        => $base_date # DateTime, yyyymmdd mmddyyyy, ddmmyyyy,
                                     ISO-1860 or even NaturalDateTime format)
    base_tz          => q/UTC/    # This is the default
 ); 

 #--Get the start and end DateTime Objects or the selected range

 my ($FirstDateTime, $LastDateTime )= @{$MoverDateNav->get_date_range()};


 #--- Where we can go next relative to the current position

 my ( $prev_params, $next_params ) =
      $MoverDateNav->get_previous_and_next_date_range_params();

 #    $prev_params = {
 #        date_unit        => $self->date_unit(),
 #        delta_date_units => 1,
 #        before_or_after  => q/before/,
 #        base_date        => 2013-09-12T12:24:22
 #    };

 #    $next_params = {
 #        date_unit        => $self->date_unit(),
 #        delta_date_units => 1,
 #        before_or_after  => q/after/,
 #        base_date        => 2013-09-12T12:24:22
 #    };


=cut

=head1 SEE ALSO

=over

 
=item *
 
 L<Convert::Input::To::DateTime>

=item *
 
 L<MooseX::Types>
  
=item *
 
 L<DateTime>
  
=item *
 
 L<Mover::Date::Types>
  
=item *

 L<Mover.pm>

=back

=cut




