REBAR=rebar

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
	./deps/amqp_client ./deps/rabbit_common ./deps/amqp_client/ebin ./deps/rabbit_common/ebin \
	 -boot start_sasl -s rabbit_farms


win_console:
	@erl -sname rabbit_farms -pa ebin \
	./deps/amqp_client ./deps/rabbit_common ./deps/amqp_client/ebin ./deps/rabbit_common/ebin \
	 -boot start_sasl -s rabbit_farms
doc:
	$(REBAR) doc

