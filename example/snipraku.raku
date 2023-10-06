#!/usr/bin/env raku

=begin pod

=head1 NAME

    snipraku.raku - Extract and run Raku snippets.

=head1 SYNOPSIS

    Run the app without arguments for help.

=end pod

# --------------------------------------------------------------------
use Code::Snippets;

my $CS;

# --------------------------------------------------------------------
sub help-exit ($msg = '') {
    note "$msg\n" if $msg;
    note qq:to/EoT/;
Usage:  ▸ ⋯ ⟨snips file⟩ ⟨snips dir⟩ ⟨option⟩ ⟨snam⟩ ⟨args⋯⟩

Possible options:

        List known snippet aliases.
    l ❲⟨snippet name glob⟩❳*

        List known snippet aliases, showing paths.
    lp ❲⟨snippet name glob⟩❳*

        Extract the files for these snippet aliases.
    x ❲⟨snippet name glob⟩❳+

        Run the main file for this snippet alias.
    r ⟨snippet name⟩ ⟨args⋯⟩

        Both extract the files for this snippet alias and run its main
        file.
    b ⟨snippet name⟩ ⟨args⋯⟩

Invocation argument examples:

    ▸ ⋯ ~/eg-raku-snips /tmp/snips-raku l eg\*
    ▸ ⋯ ~/eg-raku-snips /tmp/snips-raku b eg03

EoT

    exit 1;
}

# --------------------------------------------------------------------
sub run ($snam, *@args) {
    help-exit "No ｢$snam｣ snippet alias." unless $CS.snips{$snam};

    my $main-file = $CS.snips-dir ~ "/" ~ $CS.snips{$snam}<main>;
    chdir $main-file.IO.dirname;
    my @cmd = $*EXECUTABLE-NAME, $main-file, |@args;
    CORE::<&run>(@cmd);
}

# --------------------------------------------------------------------
proto sub MAIN (|) {
    my ($fSnips, $dSnips) = @*ARGS[0, 1];

    CATCH {
        when Code::Snippets::X {
            say .Str;
        }
        default {
            say "Some exception. " ~ .Str;
        }
    }
    $CS = Code::Snippets.build(
        snips-file  => $fSnips,
        snips-dir   => $dSnips,
        snip-bef => / ^^ "# " '-'+ "\n# ID: " .+? \n\n /,
        snip-aft => / ^^ \s* "Σ" .*? \n /,
        snip-id     => / <after ^^ "# ID:" \s+> \S+ /,
    );
    {*}
}

# --------------------------------------------------------------------
multi MAIN ($, $, 'l', *@snam-globs) {
    say $CS.snams(@snam-globs).join: "\n";
}

multi MAIN ($, $, 'lp', *@snam-globs) {
    say $CS.snams(:with-paths, @snam-globs).join: "\n";
}

multi MAIN ($, $, 'x', *@snam-globs) {
    return unless @snam-globs.elems;
    $CS.extract: @snam-globs;
}

multi MAIN ($, $, 'r', $snam, *@args) {
    run($snam, @args);
}

multi MAIN ($, $, 'b', $snam, *@args) {
    $CS.extract: $snam;
    run($snam, @args);
}

multi MAIN ($, $) {
    help-exit;
}

multi MAIN (|) { help-exit "Invalid invocation: ｢{@*ARGS.join: ' '}｣." }

