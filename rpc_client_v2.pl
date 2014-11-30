#!/usr/bin/perl

use strict;
use warnings;
use v5.010;

$|++;

use Getopt::Long;
use Parallel::ForkManager;

use AnyEvent;
use UUID::Tiny;
use Net::RabbitFoot;

use Data::Printer;

# Process the command input and setup the default for fibonacci processing
# if no input provided
# ------------------------------------------------------------------------

my @nums;
GetOptions( 
    "numbers|n=s"  => \@nums,
    "help|h"        => sub { say "perl $0 [numbers|n ]" },
);
@nums = (scalar @nums) ? split(/,/,join(',',@nums)) : qw(50 30 20 10 5);

# Declare subroutines
# -------------------

sub fibonacci($);

# --------------------------------------------------------------------
#
# Send parallelized requests to the RPC server
# --------------------------------------------

my $pm = Parallel::ForkManager->new(10);

# 1) set up data structure retrieval and handling
# -----------------------------------------------

$pm->run_on_finish( 
    sub {
      my ($pid, 
          $exit_code, $ident, $exit_signal, $core_dump, 
          $all_child_data_ref) = @_;

      if (defined $all_child_data_ref) {
        p $all_child_data_ref;
      }
      else {
        print qq|No message received from child process $pid!\n|;
      }
    }
);

# 2) send the RPC requests
# ------------------------

FIB_LOOP:
foreach my $num (@nums) {
    my $pid = $pm->start and next FIB_LOOP;
    # ----- start child process

    print " [x] Requesting fib($num)\n";
    my $response  = fibonacci($num);

    # ----- end of child process
    $pm->finish(0, { $num => $response });
}

$pm->wait_all_children;

say "[END] - all children finished";

# ---------------------------------- SUBROUTINES ---------------------------------- 

# The main subroutine for the RPC (asynchronous) request
# ------------------------------------------------------

sub fibonacci($) {
    my $n = shift;

    # set up condition variable to watch for an event (when we receive a result we asked for)
    my $cv = AnyEvent->condvar;

    # create a unique id for our request to the RPC server  
    my $corr_id = UUID::Tiny::create_UUID_as_string(UUID::Tiny::UUID_V4);

    # connect to the RabbitMQ deamon
    # (in this case on the same server, the localhost)
    my $conn = Net::RabbitFoot->new()->load_xml_spec()->connect(
        host  => 'localhost',
        port  =>  5672,
        user  => 'guest',
        pass  => 'guest',
        vhost => '/',
    );

    my $channel = $conn->open_channel();

    my $result          = $channel->declare_queue(exclusive => 1);
    my $callback_queue  = $result->{method_frame}->{queue};

    my $on_response = sub {
        my $var     = shift;
        my $body    = $var->{body}->{payload};
        if ($corr_id eq $var->{header}->{correlation_id}) {
            $cv->send($body);
        }
    };

    # callback to execute after the response from the RPC server comes back
    $channel->consume(
        no_ack      => 1,               # turning off message acknowledgment: we shall not notify the server
        on_consume  => $on_response,    # receives the server response, then makes the condition variable true,
                                        # which stops the event loop
    );

    # send the request for the fibonacci calculation to the RPC server
    $channel->publish(
        exchange    => '',
        routing_key => 'rpc_queue',     # to which queue on the server we are sending the request (ie the number
                                        # for which we want the fibonacci value
        header      => {
            reply_to        => $callback_queue,     # to which of our queues the server will send its response
            correlation_id  => $corr_id,            # identifier of our request
        },
        body => $n,                     # the number, for which we want the fibonacci value calculated
    );

    return $cv->recv;                   # callback->recv blocks until callback->send is used
                                        # returns whatever data callback->send supplies 
}

