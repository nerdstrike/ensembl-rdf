use Modern::Perl;
use Test::More;

use Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings;

my $converter = Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings->new('../xref_LOD_mapping.json');
ok ($converter);
is ($converter->identifier_org_translation('RefSeq_ncRNA'), 'http://identifiers.org/refseq/', "Test simple mapping 1");
is ($converter->identifier_org_translation('HGNC'), 'http://identifiers.org/hgnc/', "Test simple mapping 2");

my $mapping = $converter->get_mapping('Uniprot/SWISSPROT');
is($mapping->{canonical_LOD},"http://purl.uniprot.org/uniprot/","Test full mapping fetch");

done_testing;