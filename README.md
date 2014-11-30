rabbitmq
========

RPC implementation of a service providing fibonacci calculation
---------------------------------------------------------------

(inspired by https://github.com/rabbitmq/rabbitmq-tutorials/tree/master/perl)


rpc_server.pl:
-------------

                    web service for calculating fibonacci series
                    uses caching to speed up calculations for big numbers

perl rpc_server.pl


rpc_client_v2.pl:   
----------------

                    requests calculation of a list if integers
                    requests done in a parallelized manner
                    input taken from the command line. If not present then default provided

perl rpc_client_v2.p 
perl rpc_client_v2.p -n 2,66,40,150,99,5   
perl rpc_client_v2.p --number 2,66,40,150,99,5   

