
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Mover Date Navigation ",
  "AUTHOR" => "Austin Kenny <aibistin.cionnaith\@gmail.com>",
  "BUILD_REQUIRES" => {
    "Carp" => 0,
    "Data::Dump" => 0,
    "DateTime" => 0,
    "File::Spec::Functions" => 0,
    "FindBin" => 0,
    "List::MoreUtils" => 0,
    "List::Util" => 0,
    "POSIX" => 0,
    "Smart::Comments" => 0,
    "Test::Exception" => 0,
    "Test::Moose::More" => 0,
    "Test::More" => 0,
    "strict" => 0,
    "vars" => 0,
    "warnings" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Mover-Date-Navigation",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Mover::Date::Navigation",
  "PREREQ_PM" => {
    "Convert::Input::To::DateTime" => 0,
    "Log::Any" => 0,
    "Modern::Perl" => 0,
    "Moose" => 0,
    "Moose::Util::TypeConstraints" => 0,
    "MooseX::Types::Common::Numeric" => 0,
    "MooseX::Types::Common::String" => 0,
    "MooseX::Types::Moose" => 0,
    "Mover::Date::Types" => 0,
    "Readonly" => 0,
    "Scalar::Util" => 0,
    "String::Util" => 0,
    "Try::Tiny" => 0,
    "autodie" => 0,
    "namespace::autoclean" => 0
  },
  "VERSION" => "0.001",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



