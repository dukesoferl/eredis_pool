REBAR3=rebar3

all: clean compile

compile:
	@$(REBAR3) compile

clean:
	@$(REBAR3) clean

maintainer-clean: clean
	rm -rf _build

test:
	@$(REBAR3) as test eunit,cover

.PHONY: all test clean maintainer-clean
