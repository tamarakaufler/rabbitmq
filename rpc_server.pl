#!/usr/bin/perl

=head1 RPC server using RabbitMQ to provide fibonacci series calculation

=cut

use strict;
use warnings;
use v5.10;

$|++;
use AnyEvent;
use Net::RabbitFoot;

use Data::Printer;

# Declare subroutines
# -------------------
sub fib;
sub on_request;

# We shall be caching intermediate results of the recursive fib subroutine
# ------------------------------------------------------------------------
# (if we don't, calculations take an enormous amount of time for higher numbers)

my $cached = {};

# Connection to the RabbitMQ daemon
# ---------------------------------
# (in this case on the same server, the localhost)

my $conn = Net::RabbitFoot->new()->load_xml_spec()->connect(
    host  => 'localhost',
    port  =>  5672,
    user  => 'guest',
    pass  => 'guest',
    vhost => '/',
);

# Create a RabbitMQ communication channel
# ---------------------------------------

my $channel = $conn->open_channel();

# Declare which queue we shall be offering the service on
# -------------------------------------------------------
# (will provide the fibonaci series result. If we don't get any input,
#  then the result will be calculated for n=30 )

$channel->declare_queue(queue => 'rpc_queue');

# Do the calculations, when a request comes
# -----------------------------------------
# (sent to the 'rpc_queue' queue) 

$channel->consume(
    on_consume => \&on_request,
);

print " [x] Awaiting RPC requests\n";

# Wait forever
# ------------
AnyEvent->condvar->recv;

# ---------------------------------- SUBROUTINES ----------------------------------

sub fib {
    my ($n, $padding) = @_;

    $padding //= "";

    if ($n == 0 || $n == 1) {
        return $n;
    } else {
        my $n1 = $n-1;
        my $n2 = $n-2;

        $cached->{$n1} //=  fib($n1, "$padding  (-1)");
        $cached->{$n2} //=  fib($n2, "$padding  (-2)");
   
        return $cached->{$n1} + $cached->{$n2};
    }
}

sub on_request {
    my $var   = shift;                      # hashref with Net::AMQP header and body info
    my $body  = $var->{body}->{payload};        # the number for which the fibonacci calculation is requested
    my $props = $var->{header};                 # has correlation_id and reply_to queue details


    my $n = $body;
    print " [.] fib($n)\n";

    my $response = fib($n);

    # publish/send the calculation to the client's queue
    $channel->publish(
        exchange    => '',
        routing_key => $props->{reply_to},
        header      => {
            correlation_id => $props->{correlation_id},
        },
        body => $response,
    );

    $channel->ack();                        # acknoledgement that the calculation was sent, so the message/calulation can
                                            # be deleted from memory
}

