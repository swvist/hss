-module(hss_connection).
-include("hss.hrl").
-behaviour(gen_server).
-define(SERVER, ?MODULE).

-export([start_link/0, new/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).


-type connection_result() :: {ok, connection_pid()}
                           | {error, term()}.
-type cache_add_result() :: yes
                          | no.
-type cache_get_result() :: connection_pid()
                          | undefined.


%% -----------------------------------------------------------------------------
%% Public API
%% -----------------------------------------------------------------------------


-spec new(#machine{}, #credential{}) -> connection_result().
new(Machine, Credential) ->
    gen_server:call(?SERVER, {connect, Machine, Credential},
                    hss_utils:default_ssh_timeout()).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


%% -----------------------------------------------------------------------------
%% Gen server callback
%% -----------------------------------------------------------------------------


init([]) ->
    {ok, []}.

handle_call({connect, Machine, Credential}, _From, State) ->
    case create_connection(Machine, Credential) of
        {ok, ConnRef} ->
            {reply, {ok, ConnRef}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% -----------------------------------------------------------------------------
%% Internal API
%% -----------------------------------------------------------------------------


-spec cache_get(host(), username()) -> cache_get_result().
cache_get(Host, Username) ->
    global:whereis_name({conn, Host, Username}).


-spec cache_add(host(),
                username(),
                connection_pid()) -> cache_add_result().
cache_add(Host, Username, ConnRef) ->
    %% TODO: Handle registration failures.
    global:register_name({conn, Host, Username}, ConnRef).


-spec create_connection(#machine{},
                        #credential{}) -> connection_result().
create_connection(Machine, Credential) ->
    Host = hss_machine:get_host(Machine),
    Port = hss_machine:get_port(Machine),
    Username = hss_credential:get_username(Credential),
    Password = hss_credential:get_password(Credential),

    case cache_get(Host, Username) of
        undefined ->
            case ssh:connect(
                   Host, Port,
                   [{user, Username},
                    {password, Password},
                    {connect_timeout, hss_utils:default_conn_timeout()},
                    {silently_accept_hosts, hss_utils:accept_hosts()}],
                   hss_utils:default_neg_timeout()) of
                {ok, ConnRef} ->
                    cache_add(Host, Username, ConnRef),
                    {ok, ConnRef};
                {error, Reason} ->
                    {error, Reason}
            end;
        ConnRef ->
            {ok, ConnRef}
    end.
