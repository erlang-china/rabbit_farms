-include_lib("amqp_client/include/amqp_client.hrl").

-record(rabbit_farm,{ farm_name    = default,
					  amqp_params  = #amqp_params_network{},
					  feeders	   = [],
					  status 	   = inactive,
					  connection,
					  channels     = orddict:new()}).

-record(rabbit_feeder,{count = 1 , declare = #'exchange.declare'{}}).
