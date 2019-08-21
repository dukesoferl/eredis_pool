%%%-------------------------------------------------------------------
%%% @author Hiroe Shin <shin@mac-hiroe-orz-17.local>
%%% @copyright (C) 2011, Hiroe Shin
%%% @doc
%%%
%%% @end
%%% Created :  9 Oct 2011 by Hiroe Shin <shin@mac-hiroe-orz-17.local>
%%%-------------------------------------------------------------------
-module(eredis_pool).

%% Include
-include_lib("eunit/include/eunit.hrl").

%% Default timeout for calls to the client gen_server
%% Specified in http://www.erlang.org/doc/man/gen_server.html#call-3
-define(TIMEOUT, 5000).

-ifdef(OTP_RELEASE). %% this implies 21 or higher
-define(EXCEPTION(Class, Reason, Stacktrace), Class:Reason:Stacktrace).
-define(GET_STACK(Stacktrace), Stacktrace).
-else.
-define(EXCEPTION(Class, Reason, _), Class:Reason).
-define(GET_STACK(_), erlang:get_stacktrace()).
-endif.

%% API
-export([start/0, stop/0]).
-export([q/2, q/3, q/5, qp/2, qp/3, transaction/2,
         create_pool/2, create_pool/3, create_pool/4, create_pool/5,
         create_pool/6, create_pool/7, 
         delete_pool/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

start() ->
    application:start(?MODULE).

stop() ->
    application:stop(?MODULE).

%% ===================================================================
%% @doc create new pool.
%% @end
%% ===================================================================
-spec(create_pool(PoolName::atom(), Size::integer()) -> 
             {ok, pid()} | {error,{already_started, pid()}}).

create_pool(PoolName, Size) ->
    eredis_pool_sup:create_pool(PoolName, Size, []).

-spec(create_pool(PoolName::atom(), Size::integer(), Host::string()) -> 
             {ok, pid()} | {error,{already_started, pid()}}).

create_pool(PoolName, Size, Host) ->
    eredis_pool_sup:create_pool(PoolName, Size, [{host, Host}]).

-spec(create_pool(PoolName::atom(), Size::integer(), 
                  Host::string(), Port::integer()) -> 
             {ok, pid()} | {error,{already_started, pid()}}).

create_pool(PoolName, Size, Host, Port) ->
    eredis_pool_sup:create_pool(PoolName, Size, [{host, Host}, {port, Port}]).

-spec(create_pool(PoolName::atom(), Size::integer(), 
                  Host::string(), Port::integer(), Database::string()) -> 
             {ok, pid()} | {error,{already_started, pid()}}).

create_pool(PoolName, Size, Host, Port, Database) ->
    eredis_pool_sup:create_pool(PoolName, Size, [{host, Host}, {port, Port},
                                                 {database, Database}]).

-spec(create_pool(PoolName::atom(), Size::integer(), 
                  Host::string(), Port::integer(), 
                  Database::string(), Password::string()) -> 
             {ok, pid()} | {error,{already_started, pid()}}).

create_pool(PoolName, Size, Host, Port, Database, Password) ->
    eredis_pool_sup:create_pool(PoolName, Size, [{host, Host}, {port, Port},
                                                 {database, Database},
                                                 {password, Password}]).

-spec(create_pool(PoolName::atom(), Size::integer(), 
                  Host::string(), Port::integer(), 
                  Database::string(), Password::string(),
                  ReconnectSleep::integer()) -> 
             {ok, pid()} | {error,{already_started, pid()}}).

create_pool(PoolName, Size, Host, Port, Database, Password, ReconnectSleep) ->
    eredis_pool_sup:create_pool(PoolName, Size, [{host, Host}, {port, Port},
                                                 {database, Database},
                                                 {password, Password},
                                                 {reconnect_sleep, ReconnectSleep}]).


%% ===================================================================
%% @doc delet pool and disconnected to Redis.
%% @end
%% ===================================================================
-spec(delete_pool(PoolName::atom()) -> ok | {error,not_found}).

delete_pool(PoolName) ->
    eredis_pool_sup:delete_pool(PoolName).

%%--------------------------------------------------------------------
%% @doc
%% Executes the given command in the specified connection. The
%% command must be a valid Redis command and may contain arbitrary
%% data which will be converted to binaries. The returned values will
%% always be binaries.
%% @end
%%--------------------------------------------------------------------
-spec q(PoolName::atom(), Command::iolist()) ->
               {ok, undefined | binary() | [binary()]}
               | {error, pool_full | no_connection | binary()}.

q(PoolName, Command) ->
    q(PoolName, Command, ?TIMEOUT).

-spec q(PoolName::atom(), Command::iolist(), Timeout::integer()) ->
               {ok, undefined | binary() | [binary()]}
               | {error, pool_full | no_connection | binary()}.

q(PoolName, Command, Timeout) ->
  q(PoolName, Command, Timeout, Timeout, true).


-spec q(PoolName::atom(), Command::iolist(), PoolTimeout::integer(),
       EredisTimeout::integer(), Block::boolean()) ->
               {ok, undefined | binary() | [binary()]}
               | {error, pool_full | no_connection | binary()}.

q(PoolName, Command, PoolTimeout, EredisTimeout, Block) ->
    case poolboy:checkout(PoolName, Block, PoolTimeout) of
      full -> {error, pool_full};
      Worker ->
        try
            Ret = eredis:q(Worker, Command, EredisTimeout),
            case Ret of
                %% Sometimes gen_tcp returns 'closed', eredis_client worker process stays.
                %% Restart the worker process in this case.
                {error, closed} -> exit(Worker, return_closed_from_gen_tcp);
                _ -> poolboy:checkin(PoolName, Worker)
            end,
            Ret
        catch
          ?EXCEPTION(Class, Reason, Stacktrace) ->
            is_process_alive(Worker) andalso poolboy:checkin(PoolName, Worker),
            erlang:raise(Class, Reason, ?GET_STACK(Stacktrace))
        end
    end.

-spec qp(PoolName::atom(), Command::iolist(), Timeout::integer()) ->
               {ok, undefined | binary() | [binary()]}
               | {error, pool_full | no_connection | binary()}.

qp(PoolName, Pipeline) ->
    qp(PoolName, Pipeline, ?TIMEOUT).

qp(PoolName, Pipeline, Timeout) ->
    poolboy:transaction(PoolName, fun(Worker) ->
   		eredis:qp(Worker, Pipeline, Timeout)
    end).


transaction(PoolName, Fun) when is_function(Fun) ->
    F = fun(C) ->
                try
                    {ok, <<"OK">>} = eredis:q(C, ["MULTI"]),
                    Fun(C),
                    eredis:q(C, ["EXEC"])
                catch Klass:Reason ->
                        {ok, <<"OK">>} = eredis:q(C, ["DISCARD"]),
                        io:format("Error in redis transaction. ~p:~p", 
                                  [Klass, Reason]),
                        {Klass, Reason}
                end
        end,

    poolboy:transaction(PoolName, F).    
