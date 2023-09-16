unit class Code::Snippets:ver<0.2.0>:auth<zef:lucs>;

#`{{

Naming:

    snip : snippet
    snam : snippet name
    snid : snippet identifier

}}

# --------------------------------------------------------------------
use IO::Glob;

# --------------------------------------------------------------------
my token snam { (\w <[\w.-]>*) };
my token file { <-[/]>+ };
my token path { [ '/' <file> ]+ };
my token main { '!' };

grammar SnidGrammar {
    token snid { ^ <snam> [
        [ <main>  <file> ] |
        [ <main>? <path> ]
    ] $ }
}

class Snid {...}

class SnidGrammar::Actions {
    my $snam;
    my $main = False;
    my $file;
    my $path;

    method snid ($/) {
        ($path //= $file) .= subst('&', $snam, :g);
        make Snid.new(
            snid => ~$/,
            :$snam,
            :$path,
            :$main,
        );
    }

    method snam ($/) {
        $snam = ~$/;
    }

    method main ($/ = '') {
        $main = ~$/ eq "!";
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
        return $self ?? $self.ast !! Nil;
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

    #|{The file that holds the source snippets.}
has $.snips-file = "";

    #|{The directory in which the extracted snippets will be updated.}
has $.snips-dir = "";

    #|{
        snips %
            ⟨snam⟩ %
                paths %
                    ⟨path⟩ $ ⟨Snip⟩
                main $ ⟨path⟩

    }
has %.snips;

# --------------------------------------------------------------------
method build (
    Regex   :$snip-bef_rx!,
    Regex   :$snip-aft_rx!,
    Regex   :$snid_rx!,
    Str     :$snips-dir!,
    Str     :$snips-file!,
) {
    return False, "Can't read '$snips-file'." unless $snips-file.IO.f;

        # Make sure that the destination directory is writable or that
        # is can be created as such.
    given $snips-dir.IO {
        ( .d && .w)
         or ( ! .e && .mkdir && .rmdir)
         or return False, "Can't extract snips to <$snips-dir>";
    }

    my $self = Code::Snippets.new(:$snips-dir, :$snips-file);
    my $snips-text = slurp($snips-file);
    $snips-text.comb(
        /
            $<snip-bef> = [$snip-bef_rx .*? \n ]
            $<snip-txt> = .*?
            $<snip-aft> = <before [$snip-aft_rx \n] | $snip-bef_rx | $>
        /, :match
    ).map({
        my $bef = ~.<snip-bef>;
        my $txt = ~.<snip-txt>;
        my $aft = ~.<snip-aft>;
        my $snid-txt = ~($bef ~~ / <$snid_rx> /);
        my $snid = Snid.from-str($snid-txt) orelse
          return False, "Invalid snippet id expression '$snid-txt'.";

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

        $self.snips{$snam}<paths>{$path}:exists and
         return False, "Path '$path' already exists for snippet alias '$snam'.";
        $self.snips{$snam}<paths>{$path} = $snip;
        $self.snips{$snam}<main> = $path;
    });
    return True, $self;
}

# --------------------------------------------------------------------
method snals (:$with-paths = False, *@snal-globs) {
    @snal-globs.push('*') unless @snal-globs.elems;

    my @snals;
    for @snal-globs -> $glob {
        @snals.push: | self.snips.keys.grep:{ $_ ~~ glob($glob) };
    }
    @snals .= sort;

    if $with-paths {
        @snals .= map({
            my $snam = $_;
            my $main-path = 
            my @snal-paths;
            for self.snips{$snam}<paths>.keys -> $path {
                @snal-paths.push: sprintf "%s%s$path",
                    $snam,
                    (self.snips{$snam}<main> eq $path ?? ':' !! '-'),
                ;
            }
            | @snal-paths;
        });
    }

    return @snals;
}

# --------------------------------------------------------------------
method extract ($snal-want) {
    for self.snips.keys -> $snal-got {
        next unless $snal-got eq $snal-want;
        for self.snips{$snal-want}<paths>.keys -> $path {
            my $file = $.snips-dir ~ "/" ~ $path;
            $file.IO.dirname.IO.mkdir;
            my $snip = self.snips{$snal-want}<paths>{$path};
            $file.IO.spurt: .bef ~ .txt given $snip;
        }
    }

}

