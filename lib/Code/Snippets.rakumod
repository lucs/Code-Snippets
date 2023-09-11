unit class Code::Snippets;

# --------------------------------------------------------------------
my regex snal     { (<[\w]> <[\w.-]>*) };
my regex filename { <[\w.-]>+ };
my regex filepath { <[\w.-]> <[/\w.-]>* };

grammar Snalex::Grammar {
    token snalex {
        <snal> [<filenamed> | <subdired>]?
    }
    token filenamed { ([ ':' | '::' ]) <filename>? }
    token subdired  { ([ '/' | '//' ]) <filepath>? }
}

class Snalob {...}

class Snalex::Actions {
    has $.the_snal;
    has $.main  = True;
    has $.file;
    method snalex ($/) {
        make Snalob.new(
            snalex => ~$/,
            snal => ~$<snal>,
            file => $.file // ~$<snal>,
            main => $.main,
        );
    }
    method snal ($/) {
        $!the_snal = ~$/;
    }
    method filenamed ($/) {
        $!main  = False if $0 eq '::';
        $!file = ~$<filename> if $<filename>;
    }
    method subdired ($/) {
        $!main  = False if $0.substr(0, 2) eq '//';
        if $<filepath> {
            $!file = "$!the_snal/" ~ ~$<filepath>;
            $!file ~= $!the_snal if ~$/.substr(*-1) eq '/';
        }
        else {
            $!file = "$!the_snal/$!the_snal";
        }
    }
}

# --------------------------------------------------------------------
class Snalob {
    has Str $.snalex;
    has Str $.snal;
    has Str $.file;
    has Bool $.main;

    method from-str (Str $snalex) {
        note "snalex <$snalex>";
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
    has Str  $.snal;
    has Str  $.beg,
    has Str  $.txt,
    has Str  $.end,
    has Str  $.snalex;
    has Str  $.path;
    has Bool $.main;

    method build (
        $beg,
        $txt,
        $end,
        $snalex-rx,
    ) {
        my $snalex = ~($beg ~~ / $snalex-rx /);
        my $snalob = Snalob.from-str($snalex) orelse
          return False, "Invalid snippet alias expression '$snalex'.";
        my $path = $snalob.file;
        return True, self.bless:
            :snal($snalob.snal),
            :$beg,
            :$txt,
            :$end,
            :$snalex,
            :$path,
            :main($snalob.main),
        ;
    }
}

# --------------------------------------------------------------------
    #|{

    snips %
        $snal %
            $path %
                text Str
                main Bool

    }
has %.snips;

has @.errors;

    #|{The file that was used to read snippets.}
has $.snips-file = "";

    #|{The directory in which the extracted snippets will reside.}
has $.snips-dir = "";

# --------------------------------------------------------------------
method add-snip (Snip $snip) {
    my $snal = $snip.snal;
    my $path = $snip.path;
    $snal !~~ $.snips or
     $path !~~ $.snips{$snal} or
     return False, "Path '$path' already exists for snippet alias '$snal'.";
    $.snips{$snal}{$path}<text> = $snip.text;
    $.snips{$snal}{$path}<main> = $snip.main;
    return True, Nil;
}

# --------------------------------------------------------------------
method build (
    Regex   :$snip-bef_ʀ,
    Regex   :$snalex_ʀ,
    Regex   :$snip-aft_ʀ,
    Str     :$snips-dir = "/tmp",
    Str     :$snips-file,
) {
    return False, "Can't read '$snips-file'." unless $snips-file.IO.f;
    my %snips;
    my $self = Code::Snippets.new(:$snips-dir, :$snips-file, :%snips);
    my $snips-text = slurp($snips-file);
    $snips-text.comb(
        /
            $<snip-bef> = [$snip-bef_ʀ .*? \n ]
            $<snip-txt> = .*?
            $<snip-end> = <before [$snip-aft_ʀ \n] | $snip-bef_ʀ | $>
        /, :match
    ).map({
        my ($ok-snip, $snip) = Code::Snippets::Snip.build(
            ~.<snip-beg>,
            ~.<snip-txt>,
            ~.<snip-end>,
            $snalex_ʀ,
        );
        $ok-snip or $self.errors.push($snip), next;
        my $snal = $snip.snal;
        next if $snal eq 'SKIP';
        last if $snal eq 'STOP';
        my ($ok-add, $got-add) = $self.add-snip($snip);
        $ok-add or $self.errors.push($got-add);
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
method extract ($snal) {
    $snal.defined or do {
        note "No snippet alias to extract.";
        exit 1;
    }
    my @paths = %.snips{$snal}.keys.sort;
    if @paths.elems == 0 {
        note "No such ｢$snal｣ snippet alias in ｢{$.snips-file}｣.";
        exit 1;
    }
    for @paths -> $path {
        my $file = $.snips-dir ~ "/" ~ $path;
        $file.IO.dirname.IO.mkdir;
        spurt($file, %.snips{$snal}{$path}<text>);
    }
}

