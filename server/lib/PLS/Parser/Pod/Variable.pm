package PLS::Parser::Pod::Variable;

use strict;
use warnings;

use parent 'PLS::Parser::Pod';

sub new
{
    my ($class, @args) = @_;

    my %args = @args;
    my $self = $class->SUPER::new(%args);
    $self->{variable} = $args{variable};

    return $self;
} ## end sub new

sub name
{
    my ($self) = @_;

    return $self->{variable};
}

sub find
{
    my ($self, $skip_indexing) = @_;

    my ($ok, $markdown) = $self->run_perldoc_command('-Tuv', $self->{variable});
    $self->{markdown} = $markdown if $ok;
    return $ok;
} ## end sub find

1;
