package PLS::Parser::Pod::Package;

use strict;
use warnings;

use parent 'PLS::Parser::Pod';

sub new
{
    my ($class, @args) = @_;

    my %args = @args;
    my $self = $class->SUPER::new(%args);
    $self->{package} = $args{package};

    return $self;
} ## end sub new

sub name
{
    my ($self) = @_;

    return $self->{package};
}

sub find
{
    my ($self, $skip_indexing) = @_;
    my $definitions = $self->{document}{index}->find_package($self->{package}, $skip_indexing);

    if (ref $definitions eq 'ARRAY' and scalar @$definitions)
    {
        foreach my $definition (@$definitions)
        {
            my $path = URI->new($definition->{uri})->file;
            open my $fh, '<', $path or next;
            my $text = do { local $/; <$fh> };
            my ($ok, $markdown) = $self->get_markdown_from_text(\$text);

            if ($ok)
            {
                $self->{markdown} = $markdown;
                return 1;
            }
        } ## end foreach my $definition (@$definitions...)
    } ## end if (ref $definitions eq...)

    my ($ok, $markdown) = $self->get_markdown_for_package($self->{package});
    $self->{markdown} = $markdown if $ok;

    return $ok;
} ## end sub find

1;
