use Modern::Perl;
use Test::More;

use Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings;

my $converter = Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings->new('../xref_LOD_mapping.json');
ok ($converter);
is ($converter->identifier_org_translation('RefSeq_ncRNA'), 'http://identifiers.org/refseq/', "Test simple mapping 1");
is ($converter->identifier_org_translation('HGNC'), 'http://identifiers.org/hgnc/', "Test simple mapping 2");
is ($converter->identifier_org_translation('RefSeq_ncRNA_predicted'), 'http://identifiers.org/refseq/', "Test simple mapping 3");

my $mapping = $converter->get_mapping('Uniprot/SWISSPROT');
is($mapping->{canonical_LOD},"http://purl.uniprot.org/uniprot/","Test full mapping fetch");

is($converter->LOD_uri('Uniprot/SWISSPROT'),"http://purl.uniprot.org/uniprot/","Check LOD_uri() functions");
is($converter->LOD_uri('durpadurp'),"terms:durpadurp/",'Check results of a missing LOD mapping');

done_testing;