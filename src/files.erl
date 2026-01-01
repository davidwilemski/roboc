-module(files).
-export([get_cwd/0]).

% https://erlang.org/documentation/doc-5.2/lib/kernel-2.8.0/doc/html/file.html
% https://gitlab.com/greggreg/gleam_file/-/blob/master/src/gleam_file_bridge.erl
% Converts error to string
get_cwd() ->
    case file:get_cwd() of
        {ok, CurDir} ->
            Encoding = file:native_name_encoding(),
            {ok, unicode:characters_to_binary(CurDir, Encoding, unicode)};
        {error, Posix} ->
            {error, file:format_error(Posix)}
    end.
