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

-module(rabbit_farms).
-behaviour(gen_server2).

-include("rabbit_farms.hrl").
-include("rabbit_farms_internal.hrl").

-define(SERVER,?MODULE).
-define(APP,rabbit_farms).
-define(ETS_FARMS,ets_rabbit_farms).

-record(state,{status = uninitialized}).

%% API
-export([start/0, stop/0, start_link/0]).

-export([publish/2]).
-export([native_cast/2, native_cast/3]).
-export([native_call/2, native_call/3]).
-export([get_status/0]).

%% gen_server2 callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
        terminate/2, code_change/3]).

start()->
    application:start(?APP).

stop()->
    application:stop(?APP).


start_link() ->
    gen_server2:start_link({local, ?SERVER}, ?MODULE, [], []).

get_status()->
    gen_server2:call(?SERVER, {get_status}).

publish(cast, RabbitCarrot)
				when is_record(RabbitCarrot,rabbit_carrot)->
	gen_server2:cast(?SERVER, {publish, RabbitCarrot});
publish(cast, RabbitCarrots)
				when is_record(RabbitCarrots,rabbit_carrots)->
	gen_server2:cast(?SERVER, {publish, RabbitCarrots});
publish(call, RabbitCarrot)
				when is_record(RabbitCarrot,rabbit_carrot)->
	gen_server2:call(?SERVER, {publish, RabbitCarrot});
publish(call, RabbitCarrots)
				when is_record(RabbitCarrots,rabbit_carrots)->
	gen_server2:call(?SERVER, {publish, RabbitCarrots}).

native_cast(FarmName, Method)->
	gen_server2:cast(?SERVER, {native, {FarmName, Method, none}}).

native_cast(FarmName, Method, Content)->
	gen_server2:cast(?SERVER, {native, {FarmName, Method, Content}}).

native_call(FarmName, Method)->
	gen_server2:cast(?SERVER, {native, {FarmName, Method, none}}).

native_call(FarmName, Method, Content)->
	gen_server2:cast(?SERVER, {native, {FarmName, Method, Content}}).


%%%===================================================================
%%% gen_server2 callbacks
%%%===================================================================

init([]) ->
    erlang:send_after(0, self(), {init}),
    {ok, #state{}}.

handle_call({publish, RabbitCarrot}, From, State)
					when is_record(RabbitCarrot, rabbit_carrot) ->
	spawn(fun()-> 
				Reply = publish_rabbit_carrot(call, RabbitCarrot),
				gen_server2:reply(From, Reply)
		  end),
	{noreply, State};
handle_call({publish, RabbitCarrots}, From, State) 
					when is_record(RabbitCarrots,rabbit_carrots) ->
    spawn(fun()-> 
    		 Reply = publish_rabbit_carrots(call,RabbitCarrots),
    		 gen_server2:reply(From, Reply)
    	 end),
    {noreply, State};
handle_call({native, {FarmName, Method, Content}}, From, State) ->
	spawn(fun()-> 
				Reply = native_rabbit_call(call, FarmName, Method, Content),
				gen_server2:reply(From, Reply)
		  end),
	{noreply, State};
handle_call({get_status}, _From, State)->
	{reply, {ok, State}, State};
handle_call(_Request, _From, State) ->
    Reply = {error, function_clause},
    {reply, Reply, State}.

handle_cast({publish, RabbitCarrot}, State) 
					when is_record(RabbitCarrot, rabbit_carrot) ->
    spawn(fun()-> publish_rabbit_carrot(cast, RabbitCarrot) end),
    {noreply, State};
handle_cast({publish, RabbitCarrots}, State) 
					when is_record(RabbitCarrots,rabbit_carrots) ->
    spawn(fun()-> 
    		 publish_rabbit_carrots(cast, RabbitCarrots)
    	 end),
    {noreply, State};
handle_cast({native, {FarmName, Method, Content}}, State) ->
	spawn(fun()-> native_rabbit_call(cast, FarmName, Method, Content) end),
	{noreply, State};
handle_cast({on_rabbit_farm_created, RabbitFarmInstance}, State) ->
	true = ets:insert(?ETS_FARMS, RabbitFarmInstance),
	error_logger:info_msg("rabbit farm have been working:~n~p~n", [RabbitFarmInstance]),
	{noreply, State};
handle_cast({on_rabbit_farm_die, _Reason, RabbitFarm}, State) 
					when is_record(RabbitFarm, rabbit_farm) ->
    InitRabbitFarm = RabbitFarm#rabbit_farm{status = inactive, connection = undefined, channels = orddict:new()},
    true           = ets:insert(?ETS_FARMS, InitRabbitFarm),
    {noreply, State};
handle_cast(Info, State) ->
	erlang:display(Info),
    {noreply, State}.

handle_info({init}, State) ->
	ets:new(?ETS_FARMS,[protected, named_table, {keypos, #rabbit_farm.farm_name}, {read_concurrency, true}]),
	{ok, NewState} = init_rabbit_farm(State),
    {noreply, NewState};
handle_info(_Info, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

init_rabbit_farm(State)->
	{ok, Farms} = application:get_env(?APP, rabbit_farms),
	[ begin
		FarmNodeName      = ?TO_FARM_NODE_NAME(FarmName),
		{ok, FarmOptions} = application:get_env(?APP, FarmNodeName),
		RabbitFarmModel   = create_rabbit_farm_model(FarmName, FarmOptions),
		create_rabbit_farm_instance(RabbitFarmModel)
	  end
	  || FarmName <-Farms],
	{ok, State#state{status = initialized}}.

create_rabbit_farm_model(FarmName, FarmOptions) when is_list(FarmOptions)->
	UserName    = proplists:get_value(username,FarmOptions,<<"guest">>),
	Password    = proplists:get_value(password,FarmOptions,<<"V2pOV2JHTXpVVDA9">>),
	VirtualHost = proplists:get_value(virtual_host,FarmOptions,<<"/">>),
	Host        = proplists:get_value(host,FarmOptions,"localhost"),
	Port        = proplists:get_value(port,FarmOptions,5672),
	FeedsOpt	= proplists:get_value(feeders,FarmOptions,[]),
	AmqpParam	= #amqp_params_network{
						username     = ensure_binary(UserName),
						password     = Password,
						virtual_host = ensure_binary(VirtualHost),
						host         = Host,
						port         = Port
						},
	Feeders =
	[begin 
		Ticket       = proplists:get_value(ticket,FeedOpt,0),
		Exchange     = proplists:get_value(exchange,FeedOpt),
		Type         = proplists:get_value(type,FeedOpt,<<"direct">>),
		Passive      = proplists:get_value(passive,FeedOpt,false),
		Durable      = proplists:get_value(durable,FeedOpt,false),
		AutoDelete   = proplists:get_value(auto_delete,FeedOpt,false),
		Internal     = proplists:get_value(internal,FeedOpt,false),
		NoWait       = proplists:get_value(nowait,FeedOpt,false),
		Arguments    = proplists:get_value(arguments,FeedOpt,[]),
		ChannelCount = proplists:get_value(channel_count,FeedOpt,[]),
		#rabbit_feeder{ count   = ChannelCount,
						declare =
						#'exchange.declare'{
									ticket      = Ticket,
									exchange    = ensure_binary(Exchange),
									type        = ensure_binary(Type),
									passive     = Passive,
									durable     = Durable,
									auto_delete = AutoDelete,
									internal    = Internal,
									nowait      = NoWait,
									arguments   = Arguments
									}
				 	  }
	end
	||FeedOpt <- FeedsOpt],
	#rabbit_farm{farm_name = FarmName, amqp_params = AmqpParam, feeders = Feeders}.

create_rabbit_farm_instance(RabbitFarmModel)->
	#rabbit_farm{farm_name = FarmName} = RabbitFarmModel,
	FarmSups   = supervisor:which_children(rabbit_farms_sup),
	MatchedSup =
	[{Id, Child, Type, Modules} ||{Id, Child, Type, Modules} <-FarmSups, Id =:= FarmName], 
	case length(MatchedSup) > 0 of 
		false->
			supervisor:start_child(rabbit_farms_sup,{rabbit_farm_keeper_sup, {rabbit_farm_keeper_sup, start_link, [RabbitFarmModel]}, permanent, 5000, supervisor, [rabbit_farm_keeper_sup]});
		true->
			error_logger:error_msg("create rabbit farm keeper failed, farm:~n~p~n",[RabbitFarmModel])
	end,
	ok.

publish_rabbit_carrot(Type, #rabbit_carrot{
								 farm_name    = FarmName,
								 exchange     = Exchange,
								 routing_key  = RoutingKey,
								 message      = Message,
								 content_type = ContentType
							}  = RabbitCarrot)
				when is_record(RabbitCarrot,rabbit_carrot)->
	F = publish_fun(Type, Exchange, RoutingKey, Message, ContentType),
	call_warper(FarmName, F).

publish_rabbit_carrots(Type, #rabbit_carrots{
								 farm_name            = FarmName,
								 exchange             = Exchange,
								 rabbit_carrot_bodies = RabbitCarrotBodies,
								 content_type = ContentType
							}  = RabbitCarrots)
				when is_record(RabbitCarrots,rabbit_carrots)->
	 
	FunList=
	[publish_fun(Type, Exchange, RoutingKey, Message, ContentType)
	||#rabbit_carrot_body{routing_key = RoutingKey, message = Message} <- RabbitCarrotBodies],
	Funs= fun(Channel) ->
			[F(Channel)||F<-FunList]
		end,
	call_warper(FarmName, Funs).

native_rabbit_call(Type, FarmName, Method, Content)->
	F = get_fun(Type, Method, Content),
	call_warper(FarmName, F).

call_warper(FarmName, Fun) 
					when is_function(Fun,1) ->			
	case ets:lookup(?ETS_FARMS, FarmName) of 
		 [RabbitFarm] ->
		 	#rabbit_farm{connection = Connection, channels = Channels} = RabbitFarm,
		 	case is_process_alive(Connection) of 
		 		true->
				 	ChannelSize  = orddict:size(Channels),
				 	case ChannelSize > 0 of
				 		 true->
	    				 	random:seed(os:timestamp()),
							ChannelIndex = random:uniform(ChannelSize),
							Channel      = orddict:fetch(ChannelIndex, Channels),
	    				 	Ret          = Fun(Channel),
							{ok, Ret};
	    				 false->
	    				 	error_logger:error_msg("can not find channel from rabbit farm:~p~n",[FarmName])
	    			end;
				false->
					error_logger:error_msg("the farm ~p died~n",[FarmName]),
					{error, farm_died}
			end;
		 _->
		 	error_logger:error_msg("can not find rabbit farm:~p~n",[FarmName]),
		 	{error, farm_not_exist}
	end.

publish_fun(Type, Exchange, RoutingKey, Message, ContentType)->
	get_fun(Type, 
			#'basic.publish'{ exchange    = Exchange,
	    					  routing_key = ensure_binary(RoutingKey)},
	    	#amqp_msg{props = #'P_basic'{content_type = ContentType}, payload = ensure_binary(Message)}).

get_fun(cast, Method, Content)->
	fun(Channel)->
			amqp_channel:cast(Channel, Method, Content)
	end;
get_fun(call, Method, Content)->
	fun(Channel)->
			amqp_channel:call(Channel, Method, Content)
	end.

ensure_binary(undefined)->
	undefined;
ensure_binary(Value) when is_binary(Value)->
	Value;
ensure_binary(Value) when is_list(Value)->
	list_to_binary(Value).
