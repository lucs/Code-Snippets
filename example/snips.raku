# --------------------------------------------------------------------
# ID: eg01!&

sub baz (&code) {
    &code();
}

baz { say 'BAZ' };

# --------------------------------------------------------------------
# ID: eg02!/&.raku

use lib $?FILE.IO.dirname;
use Baz;

Baz.foo;

# --------------------------------------------------------------------
# ID: eg02/Baz.rakumod

class Baz {
    method foo { say 'FOO' }
}

# --------------------------------------------------------------------
# ID: STOP!&

unit module Foo;

class Bar {
    method bar { "BAR" }
}

# --------------------------------------------------------------------
# ID: misc62!/main

use lib '.';

use Foo;

    # «BAR»
say Foo::Bar.bar;
#say Foo::Bar.new.bar;

    # This is wrong.
#say Bar.new.bar;

