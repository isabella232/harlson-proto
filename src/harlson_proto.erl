-module(harlson_proto).
-export([encode/1, decode/1]).

-include("harlson_proto.hrl").

-compile({inline, [enc/1, dec/1]}).
-compile(inline).
-compile({inline_size, 200}).

-define(_int, big-unsigned-integer-unit:32).
-define(_short, big-unsigned-integer-unit:8).
-define(int, 1/?_int).
-define(short, 1/?_short).

%% ENCODER
-spec encode(rls_query()) -> binary().
encode(Query) ->
    erlang:iolist_to_binary(enc(Query)).

% Query
enc({update_metrics, QMetrics}) ->
    Len = length(QMetrics),
    [<<"UPMT", Len:?int>>, 
     [enc_metric(M) || #q_metric{} = M <- QMetrics]];
enc({update_limits, QLimits}) ->
    Len = length(QLimits),
    [<<"UPLI", Len:?int>>,
     [enc_limit(L) || #q_limit{} = L <- QLimits]];
enc({update_levels, QLevels}) ->
    Len = length(QLevels),
    [<<"UPLE", Len:?int>>,
     [enc_level(L) || #q_level{} = L <- QLevels]];
enc(get_stats) ->
    [<<"STAT">>];
enc(get_over_limit) ->
    [<<"GOVL">>];
enc(stop) ->
    [<<"STOP">>].

% QMetric
enc_metric(#q_metric{key = {Key, Endpoint},
                     count = Count}) ->
    [enc_bs(Key), enc_bs(atom_to_list(Endpoint)),
     <<Count:?int>>].

enc_limit(#q_limit{level = Level, endpoint = Endpoint,
                   limit = Limit}) ->
    [enc_bs(atom_to_list(Level)), enc_bs(atom_to_list(Endpoint)),
     <<Limit:?int>>].

enc_level(#q_level{key = Appkey, level = Level}) ->
    [enc_bs(Appkey), enc_bs(atom_to_list(Level))].

-spec enc_bs(nonempty_string()) -> iodata().
enc_bs(String) ->
    Length = length(String),
    [<<Length:?short>>, String].


%% DECODER
-spec decode(binary()) -> rls_reply().
decode(Binary) ->
    dec(Binary).

dec(<<"ROVL", Count:?int, Tail/binary>>) ->
    {OverLimit, _} = unfold_binary(Count, Tail, fun dec_r_overlimit/1),
    {overlimit, OverLimit};
dec(<<"RTEX", Count:?int, Tail:Count/binary, _Rest/binary>>) ->
    {text, Tail}.


dec_r_overlimit(<<KeySize:?short, Key:KeySize/binary, 
                  EpSize:?short, Endpoint:EpSize/binary,
                  OverLimitChange/binary>>) ->
    {OvChange, RestBin} = dec_overlimit_change(OverLimitChange),
    {#r_overlimit{key      = {binary_to_list(Key), 
                              list_to_atom(binary_to_list(Endpoint))}, 
                  change   = OvChange}, RestBin}.

dec_overlimit_change(<<0:?short, Value:?int, Throttle:?int, Rest/binary>>) ->
    {#overlimit_add{value    = Value,
                    throttle = Throttle * 1.0 / 1000000}, Rest};
dec_overlimit_change(<<1:?short, Rest/binary>>) ->
    {overlimit_removed, Rest}.
        

-spec unfold_binary(non_neg_integer(), binary(), fun((binary()) -> {X, binary()})) 
        -> {[X], binary()}.
unfold_binary(N, Binary, Fun) ->
    {Ret, RestBinary} = unfold_binary(N, Binary, Fun, []),
    {lists:reverse(Ret), RestBinary}.

unfold_binary(0, Binary, _Fun, Acc) ->
    {Acc, Binary};
unfold_binary(N, Binary, Fun, Acc) when N > 0 ->
    {Ret, RestBinary} = Fun(Binary),
    unfold_binary(N - 1, RestBinary, Fun, [Ret | Acc]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

encode_test_() ->
    [?_assertEqual(<<"GOVL">>, encode(get_over_limit)),
     ?_assertEqual(<<"STOP">>, encode(stop)),
     ?_assertEqual(<<"UPMT", 1:?int, 
                     4:?short, "test", 
                     6:?short, "search",
                     100500:?int
                   >>,
                   encode({update_metrics, [#q_metric{key = {"test", search},
                                                      count = 100500}]})),
     ?_assertEqual(<<"UPMT", 2:?int, 
                     4:?short, "test",   % 1st
                     6:?short, "search",
                     100500:?int,
                     7:?short, "testkey",   % 2nd
                     6:?short, "search",
                     10501:?int
                   >>,
                   encode({update_metrics, [#q_metric{key = {"test", search},
                                                      count = 100500},
                                            #q_metric{key = {"testkey", search},
                                                      count = 10501}]})),
     ?_assertEqual(<<"UPMT", 4:?int, 
                     4:?short, "test",      % 1st
                     6:?short, "search",
                     100500:?int,
                     7:?short, "testkey",   % 2nd
                     6:?short, "search",
                     10501:?int,
                     4:?short, "test",      % 3rd
                     6:?short, "search",
                     100500:?int,
                     7:?short, "testkey",   % 4nd
                     6:?short, "search",
                     10501:?int
                   >>,
                   encode({update_metrics, [#q_metric{key = {"test", search},
                                                      count = 100500},
                                            #q_metric{key = {"testkey", search},
                                                      count = 10501},
                                            #q_metric{key = {"test", search},
                                                      count = 100500},
                                            #q_metric{key = {"testkey", search},
                                                      count = 10501}
                                           ]})),
     ?_assertEqual(<<"UPLI", 1:?int,
                     3:?short, "std",
                     6:?short, "search",
                     1000000:?int
                   >>,
                   encode({update_limits, [#q_limit{level = std,
                                                    endpoint = search,
                                                    limit = 1000000}
                                          ]})),
     ?_assertEqual(<<"UPLI", 4:?int,
                     3:?short, "std",
                     6:?short, "search",
                     1000000:?int,
                     7:?short, "minimum",
                     6:?short, "search",
                     1000:?int,
                     4:?short, "cool",
                     6:?short, "search",
                     2000000:?int,
                     5:?short, "worst",
                     6:?short, "search",
                     2:?int
                   >>,
                   encode({update_limits, [#q_limit{level = std,
                                                    endpoint = search,
                                                    limit = 1000000},
                                           #q_limit{level = minimum,
                                                    endpoint = search,
                                                    limit = 1000},
                                           #q_limit{level = cool,
                                                    endpoint = search,
                                                    limit = 2000000},
                                           #q_limit{level = worst,
                                                    endpoint = search,
                                                    limit = 2}
                                          ]})),
     ?_assertEqual(<<"UPLE", 1:?int,
                     8:?short, "test-key",
                     6:?short, "level1"
                   >>,
                   encode({update_levels, [#q_level{key = "test-key",
                                                    level = level1}
                                          ]})),
     ?_assertEqual(<<"UPLE", 3:?int,
                     8:?short, "test-key",
                     6:?short, "level1",
                     9:?short, "test-key2",
                     6:?short, "level2",
                     10:?short, "test-key30",
                     6:?short, "level3"
                   >>,
                   encode({update_levels, [#q_level{key = "test-key",
                                                    level = level1},
                                           #q_level{key = "test-key2",
                                                    level = level2},
                                           #q_level{key = "test-key30",
                                                    level = level3}
                                          ]}))
    ].

decode_test_() ->
    [?_assertEqual({overlimit, [#r_overlimit{key = {"test", search},
                                             change = #overlimit_add{value = 100,
                                                                     throttle = 0.9}}
                               ]},
                   decode(<<"ROVL", 1:?int,
                            4:?short, "test",
                            6:?short, "search",
                            0:?short, 100:?int, 900000:?int
                          >>)),
     ?_assertEqual({overlimit, [#r_overlimit{key = {"test", search},
                                             change = #overlimit_add{value = 100,
                                                                     throttle = 1.0}},
                                #r_overlimit{key = {"testkey", search},
                                             change = overlimit_removed},
                                #r_overlimit{key = {"devel", search},
                                             change = #overlimit_add{value = 1000000,
                                                                     throttle = 0.8}},
                                #r_overlimit{key = {"general", search},
                                             change = #overlimit_add{value = 10000000,
                                                                     throttle = 0.7}}

                               ]},
                   decode(<<"ROVL", 4:?int,
                            4:?short, "test", %-
                            6:?short, "search",
                            0:?short, 100:?int, 1000000:?int,

                            7:?short, "testkey", %-
                            6:?short, "search",
                            1:?short,

                            5:?short, "devel", %-
                            6:?short, "search",
                            0:?short, 1000000:?int, 800000:?int,

                            7:?short, "general", %-
                            6:?short, "search",
                            0:?short, 10000000:?int, 700000:?int
                          >>))
    ].

-endif.

