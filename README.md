rabbit_farms
============

Rabbit farms is a standalone service for publishing messages to RabbitMQ from other another erlang apps.

#####This is a beta version.

###Usage scenario
-------

Other (external) erlang applications publish messages to RabbitMQ without needing to reference the amqp_client, 
using it just like the gen_server call/cast API.


###Usage:
-------
Configure the `rabbit_famrs.app`
`````erlang
    {env, [{rabbit_farms,[tracking]},
    	     {farm_tracking,[{username, <<"guest">>},
              						 {password, <<"V2pOV2JHTXpVVDA9">>}, %% triple_times_base64("guest")
              						 {virtual_host, <<"/">>},
              						 {host, "localhost"},
              						 {port, 5672},
                           {feeders,[
                                      [{channel_count,1},
                                       {exchange, <<"tracking.logs">>},
                                       {type, <<"topic">>}]
                                    ]}
                           ]}
    ]}
`````
####publish 
`````erlang
    1>RabbitCarrot = #rabbit_carrot{farm_name = tracking, exchange = <<"tracking.logs">>, 
                     routing_key = <<"routing_key">>, 
                     message = <<"">>}.
      #rabbit_carrot{farm_name = tracking,
               exchange = <<"tracking.logs">>,
               routing_key = <<"routing_key">>,message = <<>>,
               content_type = undefined}

    2>rabbit_farms:publish(cast, RabbitCarrot). %%asynchronous
    3>rabbit_farms:publish(call, RabbitCarrot). %%synchronization
`````
####batch publish
`````erlang
    1>Body1 = #rabbit_carrot_body{routing_key = <<"routing_key">>, message = <<"message1">>}.
      #rabbit_carrot_body{routing_key = <<"routing_key1">>,
                    message = <<"message1">>}
                    
    2>Body2 = #rabbit_carrot_body{routing_key = <<"routing_key">>, message = <<"message2">>}.
      #rabbit_carrot_body{routing_key = <<"routing_key2">>,
                    message = <<"message2">>}
                    
    3>RabbitCarrots = #rabbit_carrots{farm_name            = tracking,
                                      exchange             = <<"tracking.logs">>, 
                                      rabbit_carrot_bodies = [Body1,Body2]}.
    
      #rabbit_carrots{
                        farm_name = tracking,exchange = <<"tracking.logs">>,
                        rabbit_carrot_bodies = 
                            [#rabbit_carrot_body{
                                 routing_key = <<"routing_key">>,
                                 message = <<"message1">>},
                             #rabbit_carrot_body{
                                 routing_key = <<"routing_key">>,
                                 message = <<"message2">>}],
                        content_type = undefined}

    4>rabbit_farms:publish(cast, RabbitCarrots). %%asynchronous
    5>rabbit_farms:publish(call, RabbitCarrots). %%synchronization
`````
