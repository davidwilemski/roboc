-module(roboc_ffi).
-export([read_line_utf8/0]).

%% Read a line from standard input with UTF-8 encoding support
%% Returns {ok, Line} or {error, nil} on EOF or error
read_line_utf8() ->
    case io:get_line("") of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Line when is_list(Line) ->
            %% Convert from list to binary (Gleam string)
            {ok, unicode:characters_to_binary(Line, utf8)};
        Line when is_binary(Line) ->
            {ok, Line}
    end.
