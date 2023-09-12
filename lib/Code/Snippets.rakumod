unit class Code::Snippets;

my %*SUB-MAIN-OPTS = :named-anywhere;

#`{{

Nomenclature

    snip    : snippet
    snip-bef: before-snippet marker
    snip-aft: after-snippet marker
    snal    : snippet alias
    snalex  : snippet alias expression
    snalob  : snippet alias object

}}

# --------------------------------------------------------------------
use IO::Glob;

# --------------------------------------------------------------------
my regex snal     { (<[\w]> <[\w.-]>*) };
my regex filename { <[\w.-]>+ };
my regex filepath { <[\w.-]> <[/\w.-]>* };

grammar Snalex::Grammar {
    token snalex    { <snal> [<filenamed> | <subdired>]? }
    token filenamed { ([ ':' | '::' ]) <filename>? }
    token subdired  { ([ '/' | '//' ]) <filepath>? }
}

class Snalob {...}

class Snalex::Actions {
    has $.the_snal;
    has $.main  = True;
    has $.path;
    method snalex ($/) {
        make Snalob.new(
            snalex => ~$/,
            snal => ~$<snal>,
            path => $.path // ~$<snal>,
            main => $.main,
        );
    }
    method snal ($/) {
        $!the_snal = ~$/;
    }
    method filenamed ($/) {
        $!main  = False if $0 eq '::';
        $!path = ~$<filename> if $<filename>;
    }
    method subdired ($/) {
        $!main  = False if $0.substr(0, 2) eq '//';
        if $<filepath> {
            $!path = "$!the_snal/" ~ ~$<filepath>;
            $!path ~= $!the_snal if ~$/.substr(*-1) eq '/';
        }
        else {
            $!path = "$!the_snal/$!the_snal";
        }
    }
}

# --------------------------------------------------------------------
class Snalob {
    has Str $.snalex;
    has Str $.snal;
    has Str $.path;
    has Bool $.main;

    method from-str (Str $snalex) {
        my $snalex-parsed = Snalex::Grammar.parse(
            $snalex,
            rule => 'snalex',
            :actions(Snalex::Actions.new),
        );
        return $snalex-parsed ?? $snalex-parsed.ast !! Nil;
    }
}

# --------------------------------------------------------------------
class Snip {
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
            ⟨snal⟩ %
                paths %
                    ⟨path⟩ $ ⟨Snip⟩
                main $ ⟨path⟩

    }
has %.snips;

# --------------------------------------------------------------------
method build (
    Regex   :$snip-bef_rx,
    Regex   :$snip-aft_rx,
    Regex   :$snalex_rx,
    Str     :$snips-dir = "/tmp",
    Str     :$snips-file,
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
        my $snip = Code::Snippets::Snip.new(
            bef => ~.<snip-bef>,
            txt => ~.<snip-txt>,
            aft => ~.<snip-aft>,
        );
        my $snalex = ~($snip.bef ~~ / <$snalex_rx> /);
        my $snalob = Snalob.from-str($snalex) orelse
          return False, "Invalid snippet alias expression '$snalex'.";

        my $snal = $snalob.snal;

        next if $snal eq 'SKIP';
        last if $snal eq 'STOP';

        my $path = $snalob.path;
        my $main = $snalob.main;

        $self.snips{$snal}<paths>{$path}:exists and
         return False, "Path '$path' already exists for snippet alias '$snal'.";
        $self.snips{$snal}<paths>{$path} = $snip;
        $self.snips{$snal}<main> = $path;
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
            my $snal = $_;
            my $main-path = 
            my @snal-paths;
            for self.snips{$snal}<paths>.keys -> $path {
                @snal-paths.push: sprintf "%s%s$path",
                    $snal,
                    (self.snips{$snal}<main> eq $path ?? ':' !! '-'),
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

