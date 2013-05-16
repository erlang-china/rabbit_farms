%% -------------------------------------------------------------------
%% Copyright (c) 2013 Xujin Zheng (zhengxujin@adsage.com)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%% -------------------------------------------------------------------

-module(rabbit_farm_keeper).

-behaviour(gen_server2).

-include("rabbit_farms.hrl").
-include("rabbit_farms_internal.hrl").

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(RABBIT_FARMS,rabbit_farms).
-define(SERVER,?MODULE).
-define(RECONNECT_TIME,5000).
%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/1, get_status/1]).

start_link(RabbitFarmModel) ->
	#rabbit_farm{farm_name = FarmName} = RabbitFarmModel,
    gen_server2:start_link({local, ?TO_FARM_NODE_NAME(FarmName)}, ?MODULE, [RabbitFarmModel], []).

get_status(FarmName) ->
	FarmNode = ?TO_FARM_NODE_NAME(FarmName),
    gen_server2:call(FarmNode,{get_status}).

%% ====================================================================
%% Behavioural functions 
%% ====================================================================
-record(state, {status = inactive, rabbit_farm = #rabbit_farm{}}).

init([RabbitFarm]) when is_record(RabbitFarm, rabbit_farm)->
    erlang:send_after(0, self(), {init, RabbitFarm}),
    {ok, #state{}}.

handle_call({get_status}, _From, State)->
	{reply, {ok, State}, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({on_rabbit_farm_die,Reason,RabbitFarm}, State) 
					when is_record(RabbitFarm,rabbit_farm) ->
    NewState = State#state{status = inactive, rabbit_farm = RabbitFarm#rabbit_farm{connection = undefined, channels = orddict:new()}},
    Server = self(),
    spawn_link(fun()->
		try 
			erlang:send_after(?RECONNECT_TIME, Server, {init, RabbitFarm})
	    catch
	    	Class:Reason -> {Class, Reason} 
	    end
  	end),
    {noreply, NewState};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({init, RabbitFarm}, State) ->
	NewState = 
	case create_rabbit_farm_instance(RabbitFarm) of 
		{ok, FarmInstance}->
			gen_server2:cast(?RABBIT_FARMS,{on_rabbit_farm_created,FarmInstance}),
			State#state{status = actived, rabbit_farm = FarmInstance};
		_->
			State#state{status = inactive}
	end,
	{noreply, NewState};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================
create_rabbit_farm_instance(#rabbit_farm{amqp_params    = AmqpParams,
		 		  		   				 feeders        = Feeders} = Farm) 
								when is_record(Farm,rabbit_farm)->
	SecPassword	 	 = AmqpParams#amqp_params_network.password,
	DecodedAmqpParms = AmqpParams#amqp_params_network{password = decode_base64(SecPassword)},
	Keeper           = self(),
	case amqp_connection:start(DecodedAmqpParms) of
		{ok, Connection}->
				watch_rabbit_farm( Keeper,
								   Connection,
								   Farm, 
								   fun(KP, CON, RBI, RS)-> 
								   		on_rabbit_farm_exception(KP, CON, RBI, RS)
								   end
								   ),

				ChannelList = lists:flatten( [[ 
										  	begin 
												{ok, Channel}           = amqp_connection:open_channel(Connection),
												{'exchange.declare_ok'} = amqp_channel:call(Channel,Declare),
												Channel
										    end
									  	    || _I <-lists:seq(1,ChannelCount)]
									   	  || #rabbit_feeder{count = ChannelCount,declare = Declare} <- Feeders]),
				IndexedChannels =  lists:zip(lists:seq(1,length(ChannelList)),ChannelList),
				Channels        =  orddict:from_list(IndexedChannels),
				{ok, Farm#rabbit_farm{connection = Connection, channels = Channels, status = actived}};
		{error,Reason}->
				{error, Reason}
	end.
	
on_rabbit_farm_exception(Keeper, Connection, RabbitFarmInstance, Reason)->
	gen_server2:cast(?RABBIT_FARMS,{on_rabbit_farm_die,Reason,RabbitFarmInstance}),
	gen_server2:cast(Keeper, {on_rabbit_farm_die,Reason,RabbitFarmInstance}),
	error_logger:error_msg("connection_pid:~n~p~nrabbit_farm:~n~p~nreason:~n~p~n",[Connection,RabbitFarmInstance,Reason]).

watch_rabbit_farm(Keeper, Connection, RabbitFarm, Fun) when   
												 is_pid(Keeper),
												 is_pid(Connection),
									 			 is_record(RabbitFarm,rabbit_farm)->
	 spawn_link(fun() ->
				process_flag(trap_exit, true),
				link(Connection),
				link(Keeper),
			 	receive
			 		{'EXIT', Connection, Reason} -> 
			 			Fun(Keeper, Connection, RabbitFarm, Reason);
			 		{'EXIT', Keeper, _Reason} -> 
			 			amqp_connection:close(Connection)
	 			end
 	end).

decode_base64(Value)->
	B1 = base64:decode(Value),
	B2 = base64:decode(B1),
	base64:decode(B2).