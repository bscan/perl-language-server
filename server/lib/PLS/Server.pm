package PLS::Server;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Loop;
use Coro;
use Coro::Channel;
use JSON;
use List::Util qw(first);
use Scalar::Util;

use PLS::Server::Request;
use PLS::Server::Response;

sub new
{
    my ($class) = @_;

    return bless {}, $class;
}

sub recv
{
    my ($self) = @_;

    my %headers;
    my $line;
    my $buffer;

    while (sysread STDIN, $buffer, 1)
    {
        $line .= $buffer;
        last if $line eq "\r\n";
        next unless $line =~ /\r\n$/;
        $line =~ s/^\s+|\s+$//g;
        my ($field, $value) = split /: /, $line;
        $headers{$field} = $value;
        $line = '';
    } ## end while (sysread STDIN, $buffer...)

    my $size = $headers{'Content-Length'};
    die 'no Content-Length header provided' unless $size;

    my $raw;
    my $length = sysread STDIN, $raw, $size;
    die 'content length does not match header' unless $length == $size;
    my $content = decode_json $raw;

    if (length $content->{method})
    {
        return PLS::Server::Request->new($content);
    }
    else
    {
        return PLS::Server::Response->new($content);
    }
} ## end sub recv

sub send
{
    my ($self, $response) = @_;

    my $json = $response->serialize;
    my $size = length $json;

    syswrite STDOUT, "Content-Length: $size\r\n\r\n$json";
} ## end sub send

sub run
{
    my ($self) = @_;

    my $client_requests  = Coro::Channel->new;
    my $server_responses = Coro::Channel->new;
    my $server_requests  = Coro::Channel->new;
    my $client_responses = Coro::Channel->new;

    $self->{server_requests} = $server_requests;

    my $last_request_id = 0;
    my @pending_requests;

    async
    {
        # check for requests and service them
        while (my $request = $client_requests->get)
        {
            async
            {
                my ($request) = @_;
                my $response = $request->service($self);
                return unless Scalar::Util::blessed($response);
                $server_responses->put($response);
            } ## end async
            $request;

            Coro::cede();
        } ## end while (my $request = $client_requests...)
    };

    async
    {
        # check for responses and send them
        while (my $response = $server_responses->get)
        {
            async
            {
                my ($response) = @_;
                $self->send($response);
            }
            $response;

            Coro::cede();
        } ## end while (my $response = $server_responses...)
    };

    async
    {
        while (my $request = $server_requests->get)
        {
            $request->{id} = ++$last_request_id;
            push @pending_requests, $request;

            async
            {
                my ($request) = @_;
                $self->send($request);
            }
            $request;

            Coro::cede();
        } ## end while (my $request = $server_requests...)
    };

    async
    {
        while (my $response = $client_responses->get)
        {
            my $request = first { $_->{id} == $response->{id} } @pending_requests;
            next unless Scalar::Util::blessed($request);
            @pending_requests = grep { $_->{id} != $response->{id} } @pending_requests;

            async
            {
                my ($request, $response) = @_;
                $request->handle_response($response);
            }
            $request, $response;

            Coro::cede();
        } ## end while (my $response = $client_responses...)
    };

    my $io_watcher = AnyEvent->io(
        fh   => \*STDIN,
        poll => 'r',
        cb   => sub {
            my $message = $self->recv();
            return unless Scalar::Util::blessed($message);

            if ($message->isa('PLS::Server::Request'))
            {
                $client_requests->put($message);
            }
            if ($message->isa('PLS::Server::Response'))
            {
                $client_responses->put($message);
            }
        }
    );

    AnyEvent::Loop::run();
} ## end sub run

1;
