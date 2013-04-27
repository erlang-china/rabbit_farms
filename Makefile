REBAR=../compile_tools/rebar/rebar

.PHONY: all erl test clean doc 

all: compile

compile:
	@$(REBAR) get-deps compile

test: all
	@mkdir -p .eunit
	$(REBAR) skip_deps=true eunit

clean:
	$(REBAR) clean
	-rm -rvf deps ebin doc .eunit

console:
	@erl -sname rabbit_farms -pa ebin \
	../libs/amqp_client ../libs/rabbit_common ../libs/amqp_client/ebin ../libs/rabbit_common/ebin \
	 -boot start_sasl -s rabbit_farms


win_console:
	@werl -sname rabbit_farms -pa ebin \
	../libs/amqp_client ../libs/rabbit_common ../libs/amqp_client/ebin ../libs/rabbit_common/ebin \
	 -boot start_sasl -s rabbit_farms
doc:
	$(REBAR) doc

