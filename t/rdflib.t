use Modern::Perl;
use Test::More;
use Test::Exports;
use Bio::EnsEMBL::RDF::RDFlib qw/triple prefix u triple escape name_spaces new_bnode/;

import_ok('Bio::EnsEMBL::RDF::RDFlib', [qw/prefix name_spaces u triple escape/],'RDFlib imports correctly');

ok(name_spaces(),'Check there name spaces available');

is(prefix('faldo'),'http://biohackathon.org/resource/faldo#','Fetch prefix');
is(triple('a:b','ra:ca','dab:ra'), "a:b ra:ca dab:ra .\n", 'Checking the obvious');

cmp_ok(new_bnode,'eq','_1','bnode generator');
cmp_ok(new_bnode,'eq','_2','bnode generator increments properly');

done_testing;