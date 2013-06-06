-record(rabbit_carrot,{ farm_name   = default, 
                        exchange    = <<"">>, 
                        routing_key = <<"">>, 
                        message     = <<"">>,
                        content_type}).

-record(rabbit_carrot_body,{routing_key = <<"">>, message = <<"">>}).

-record(rabbit_carrots,{ farm_name            = default, 
                         exchange             = <<"">>, 
                         rabbit_carrot_bodies = [],
                         content_type}).

