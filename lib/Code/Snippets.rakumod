unit class Code::Snippets;

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
    Regex   :$snip-bef_ʀ,
    Regex   :$snip-aft_ʀ,
    Regex   :$snalex_ʀ,
    Str     :$snips-dir = "/tmp",
    Str     :$snips-file,
) {
    return False, "Can't read '$snips-file'." unless $snips-file.IO.f;
    my $self = Code::Snippets.new(:$snips-dir, :$snips-file);
    my $snips-text = slurp($snips-file);
    $snips-text.comb(
        /
            $<snip-bef> = [$snip-bef_ʀ .*? \n ]
            $<snip-txt> = .*?
            $<snip-aft> = <before [$snip-aft_ʀ \n] | $snip-bef_ʀ | $>
        /, :match
    ).map({
        my $snip = Code::Snippets::Snip.new(
            bef => ~.<snip-bef>,
            txt => ~.<snip-txt>,
            aft => ~.<snip-aft>,
        );
        my $snalex = ~($snip.bef ~~ / <$snalex_ʀ> /);
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
method list-snals () {
    self.snips.keys.sort;
}

method list-paths (Str $snal) {
    self.snips{$snal}.keys.sort;
}

    #|{
    Extracts the requested snal snippets to disk. Throws an exception
    if unable to.
    }
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

