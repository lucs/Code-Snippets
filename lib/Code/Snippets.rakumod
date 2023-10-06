unit class Code::Snippets:ver<0.3.1>:auth<zef:lucs>;

#`{{

Naming:

    snip : snippet
    snam : snippet name, ⦃eg01⦄
    snid : snippet identifier, ⦃eg01!/main.raku⦄

}}

# --------------------------------------------------------------------
use IO::Glob;

# --------------------------------------------------------------------
class X is Exception {
    has $.msg;
    method message { $.msg }
}

class X::NoSuchSnipsFile is X { }

class X::CantWriteToDir is X { }

class X::BadSnid is X {
    has $.snid;
    has $.other-msg;
    method message {
        $.other-msg // "Bad snippet id '{$.snid}'.";
    }
}

# --------------------------------------------------------------------
grammar SnidGrammar {
    token snam { (\w <[\w.-]>*) }
    token file { <-[/]>+ }
    token path { [ '/' <file> ]+ }
    token main { '!' }
    token snid { ^ <snam> [
        [ <main>  <file> ] | [ <main>? <path> ]
    ] $ }
}

class Snid {...}

class SnidGrammar::Actions {
    my $snam;
    my $main;
    my $file;
    my $path;

    method snid ($/) {
        ($path //= $file) .= subst('&', $snam, :g);
       # note "in snid {~$/} main <$main>";
        make Snid.new(
            snid => ~$/,
            :$snam,
            :$path,
            :$main,
        );
    }

    method snam ($/) {
        $snam = ~$/;
            # Reset values.
       # note "Resetting";
        $main = False;
        $file = Nil;
        $path = Nil;
    }

    method main ($/ = '') {
       # note ~$/, " is tilde main";
        $main = ~$/ eq "!";
       # note "main <$main>";
    }

    method file ($/) {
        $file = ~$/;
    }

    method path ($/) {
        $path = $snam ~ ~$/;
    }

}

# --------------------------------------------------------------------
class Snid {
    has Str  $.snid;
    has Str  $.snam;
    has Str  $.path;
    has Bool $.main;

    method from-str (Str $snid) {
        my $self = SnidGrammar.parse(
            $snid,
            rule => 'snid',
            :actions(SnidGrammar::Actions.new),
        );
        X::BadSnid.new(:$snid).throw unless $self.defined;
        return $self.ast;
    }

}

# --------------------------------------------------------------------
class Snip {
    has Snid $.snid;
    has Str  $.bef,
    has Str  $.txt,
    has Str  $.aft,
}

# --------------------------------------------------------------------

    # The file that holds the source snippets.
has $.snips-file = "";

    # The directory in which the extracted snippets will be placed.
has $.snips-dir = "";

    #`(
        The snippets found in the snippets file.

        snips %
            ⟨snam⟩ %
                paths %
                    ⟨path⟩ $ ⟨Snip⟩
                main $ ⟨path⟩

    )
has %.snips;

# --------------------------------------------------------------------
method build (
    Regex   :$snip-bef!,
    Regex   :$snip-aft!,
    Regex   :$snip-id!,
    Str     :$snips-dir!,
    Str     :$snips-file!,
) {
    X::NoSuchSnipsFile.new(
        msg => "Can't read file <$snips-file>."
    ).throw unless .f && .r given $snips-file.IO;

        # Make sure that the destination directory is writable or that
        # it can be created as such.
    given $snips-dir.IO {
        (.d && .w)
        or (! .e && .mkdir && .rmdir)
        or X::CantWriteToDir.new(
            msg => "Can't extract snips to <$snips-dir>."
        ).throw;
    }

    my $self = Code::Snippets.new(:$snips-dir, :$snips-file);
    my $snips-text = slurp($snips-file);
    $snips-text.comb(
        /
            $<snip-bef> = $snip-bef
            $<snip-txt> = .*?
            $<snip-aft> = <before $snip-aft | $snip-bef | $>
        /, :match
    ).map({
        my $bef = ~.<snip-bef>;
        my $txt = ~.<snip-txt> // '';
        my $aft = ~.<snip-aft> // '';
        my $snid-txt = ~($bef ~~ / <$snip-id> /);
        try my $snid = Snid.from-str($snid-txt);
        if $! ~~ X::BadSnid {
            X::BadSnid.new(
                snid => $snid-txt,
                other-msg => "Bad snippet id <$snid-txt> in file <$snips-file>."
            ).throw;
        }

        my $snip = Code::Snippets::Snip.new:
            :$snid,
            :$bef,
            :$txt,
            :$aft,
        ;
        my $snam = $snip.snid.snam;

        next if $snam eq 'SKIP';
        last if $snam eq 'STOP';

        my $path = $snip.snid.path;
        my $main = $snip.snid.main;

        $self.snips{$snam}<paths>{$path}:exists and X.new(
            msg => "Path '$path' already exists for snippet alias '$snam'."
        ).throw;
        $self.snips{$snam}<paths>{$path} = $snip;
        $self.snips{$snam}<main> = $path if $main;
    });
    return $self;
}

# --------------------------------------------------------------------
method snams (:$with-paths = False, *@snam-globs) {
    @snam-globs.push('*') unless @snam-globs.elems;

    my @snams;
    for @snam-globs -> $glob {
        @snams.push: | self.snips.keys.grep:{ $_ ~~ glob($glob) };
    }
    @snams .= sort;

    if $with-paths {
        @snams .= map({
            my $snam = $_;
            my @snam-paths;
            for self.snips{$snam}<paths>.keys -> $path {
                @snam-paths.push: sprintf "%s%s$path",
                    $snam,
                    (self.snips{$snam}<main> eq $path ?? ':' !! '-'),
                ;
            }
            | @snam-paths;
        });
    }

    return @snams;
}

# --------------------------------------------------------------------
method extract (
    :&content = sub (
        $bef,
        $txt,
        $aft,
        :$append = False,
    ) { return $bef ~ $txt },
    *@snam-globs,
) {
    my @snams;
    for @snam-globs -> $glob {
        @snams.push: | self.snips.keys.grep:{ $_ ~~ glob($glob) };
    }
    for @snams -> $snam {
        for self.snips{$snam}<paths>.keys -> $path {
            my $file = $.snips-dir ~ "/" ~ $path;
            $file.IO.dirname.IO.mkdir;
            my $snip = self.snips{$snam}<paths>{$path};
            $file.IO.spurt: &content(.bef, .txt, .aft) given $snip;
        }
    }

}

