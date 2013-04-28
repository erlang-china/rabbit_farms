REBAR=rebar

.PHONY: all erl test clean doc 

all:deps compile

compile:
	@$(REBAR) compile

deps:
	@$(REBAR) get-deps

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

APPS = kernel stdlib sasl erts ssl crypto inets eunit syntax_tools compiler

CODE_PLT = ./rabbit_farms_dialyzer_plt

check_plt: compile
	dialyzer --check_plt --plt $(CODE_PLT) --apps $(APPS) \
		./ebin \
		deps/*/ebin

build_plt: compile
	dialyzer --build_plt --output_plt $(CODE_PLT) --apps $(APPS) \
		./ebin \
		deps/*/ebin

dialyzer: compile
	@echo
	@echo Use "'make check_plt'" to check PLT prior to using this target.
	@echo Use "'make build_plt'" to build PLT prior to using this target.
	@echo
	@sleep 1
	dialyzer -Wno_return --plt $(CODE_PLT) ./ebin | \
	    fgrep -v -f ./dialyzer.ignore-warnings

cleanplt:
	@echo 
	@echo "Are you sure?  It takes about 1/2 hour to re-build."
	@echo Deleting $(CODE_PLT) in 5 seconds.
	@echo 
	sleep 5
	rm $(CODE_PLT)