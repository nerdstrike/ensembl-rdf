use Modern::Perl;
use Test::More;
use Test::Differences;
use List::Compare;

use Bio::EnsEMBL::RDF::EnsemblToTripleConverter;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Test::MultiTestDB;

use Bio::EnsEMBL::BulkFetcher;
use Data::Dumper;
use RDF::Trine;
use RDF::Query;

my $test_db = Bio::EnsEMBL::Test::MultiTestDB->new('ontology' );
my $surplus_db = Bio::EnsEMBL::Test::MultiTestDB->new('homo_sapiens' );
my $dba = $test_db->get_DBAdaptor('ontology');
my $dbb = $surplus_db->get_DBAdaptor('core');

my $fake_file;
my $fh;
ok ( open($fh,'>',\$fake_file) );

my $converter = Bio::EnsEMBL::RDF::EnsemblToTripleConverter->new({
  ontology_adaptor => $dba->get_OntologyTermAdaptor(),
  meta_adaptor => $dbb->get_MetaContainer(),
  species => 'homo_sapiens',
  production_name => 'homo_sapiens',
  xref => 1,
  release => 82,
  xref_mapping_file => '../xref_LOD_mapping.json',
  main_fh => $fh
});
is ($converter->production_name,'homo_sapiens',"Constructor assignments");
is ($converter->release,'82',"Constructor assignments");

my $slice_adaptor = $dbb->get_SliceAdaptor();
my $slices = $slice_adaptor->fetch_all('chromosome');
$converter->print_namespaces();
$converter->print_species_info();
$converter->print_seq_regions($slices);

my $fetcher = Bio::EnsEMBL::BulkFetcher->new();
# These are NOT proper Gene objects, they are hash summaries.
my $genes = $fetcher->export_genes($dbb,undef,'translation',1);
my ($gene) = grep { $_->{id} eq 'ENSG00000214717'} @$genes;

$converter->print_feature($gene, $converter->generate_feature_uri($gene->{id},'gene'), 'gene');

close $fh;
print $fake_file."\n\n";
# Compare output against "proper" RDF library.
my $store = RDF::Trine::Store::Memory->new();
my $model = RDF::Trine::Model->new($store);
my $parser = RDF::Trine::Parser->new('turtle');

$parser->parse_into_model('http://rdf.ebi.ac.uk/resource/ensembl/', $fake_file, $model);

my $prefixes = qq[PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX dc: <http://purl.org/dc/elements/1.1/>
PREFIX faldo: <http://biohackathon.org/resource/faldo#>
PREFIX sio: <http://semanticscience.org/resource/>
PREFIX ensembl: <http://rdf.ebi.ac.uk/resource/ensembl/>
PREFIX term: <http://rdf.ebi.ac.uk/terms/ensembl/>
PREFIX ensemblvariation: <http://rdf.ebi.ac.uk/terms/ensemblvariation/>
PREFIX transcript: <http://rdf.ebi.ac.uk/resource/ensembl.transcript/>
PREFIX ensembl_variant: <http://rdf.ebi.ac.uk/resource/ensembl.variant/>
PREFIX protein: <http://rdf.ebi.ac.uk/resource/ensembl.protein/>
PREFIX exon: <http://rdf.ebi.ac.uk/resource/ensembl.exon/>
PREFIX identifiers: <http://identifiers.org/>
];

# Test seq region labels
my $sparql = "
$prefixes
SELECT ?label WHERE {
  ?seq_region rdfs:subClassOf obo:SO_0000340 .
  ?seq_region rdfs:label ?label .
}";
my @result = query($sparql);
my @strings = map { $_->{label}->as_string } @result; 

is_deeply(\@strings, ['"Homo sapiens chromosome chromosome:GRCh38:6:1:170805979:1"','"Homo sapiens chromosome chromosome:GRCh38:X:1:156040895:1"','"Homo sapiens chromosome chromosome:GRCh38:Y:1:57227415:1"'], 'Seq regions returned with correct labels');

# Test gene
$sparql = qq[
$prefixes
SELECT ?start ?end WHERE {
  ?feature dc:identifier "ENSG00000214717" .
  ?feature faldo:location ?faldo .
  ?faldo faldo:begin ?begin .
  ?begin faldo:position ?start .
  ?faldo faldo:end ?otherend .
  ?otherend faldo:position ?end .
} ];

@result = query($sparql);
cmp_ok( $result[0]->{start}->numeric_value, '==', 2500967 ,'Gene start correct');
cmp_ok( $result[0]->{end}->numeric_value, '==', 2486414, 'Gene end correct');

# Test gene-transcript relations

$sparql = qq[
$prefixes
SELECT ?transcript WHERE {
  ?feature dc:identifier "ENSG00000214717" .
  ?transcript_uri obo:SO_transcribed_from ?feature .
  ?transcript_uri dc:identifier ?transcript .
}
];

@result = query($sparql);
my $comparator = List::Compare->new([ map {$_->{transcript}->value} @result],[qw/ENST00000461691 ENST00000381222 ENST00000381223 ENST00000381218 ENST00000515319/]);
# eq_or_diff( [map {$_->{transcript}->value} @result], [qw/ENST00000461691 ENST00000381222 ENST00000381223 ENST00000381218 ENST00000515319/], "Transcript stable IDs returned for given gene");
cmp_ok($comparator->get_symmetric_difference(), '==', 0, "Transcript stable IDs returned for given gene");

$sparql = qq[
$prefixes
SELECT ?translation WHERE {
  ?feature dc:identifier "ENST00000461691" .
  ?feature obo:SO_translates_to ?translation_uri .
  ?translation_uri dc:identifier ?translation .
}
];

@result = query($sparql);
@result = map {$_->{translation}->value} @result;
is_deeply( \@result, [qw/ENSP00000419148/],"Translations connected to transcript");

sub query {
  my $sparql = shift;
  my $query = RDF::Query->new($sparql) || die RDF::Query->error;
  @result = $query->execute($model);
  return @result;
}

# Testing INSDC accessions. Don't have suitable test data.
# $sparql = qq[$prefixes
# SELECT ?insdc ?feature WHERE {
#   ?feature dc:identifier "ENSG00000214717" .
#   ?feature sio:equivalentTo ?uri .
#   ?uri dc:identifier ?insdc .
# }];

# @result = query($sparql);

# cmp_ok($result[0]->{insdc}, 'eq', 'altX','INSDC synonym for seq_region mapped correctly');
# Test exons
$sparql = qq[$prefixes
SELECT ?exon_id ?rank WHERE {
  ?transcript dc:identifier "ENST00000381223" .
  ?transcript sio:SIO_000974 ?exon_collection .
  ?exon_collection sio:SIO_000628 ?exon .
  ?exon rdfs:label ?exon_id .
  ?exon_collection sio:SIO_000300 ?rank .
} ORDER BY ?rank
];
@result = query($sparql);

cmp_ok(@result, '==', 2, 'Two exons attached to a transcript');
is_deeply([map {$_->{exon_id}->value} @result],['ENSE00001413450','ENSE00002295224'],'Exon IDs correct and in correct order');

$sparql = qq[$prefixes
SELECT ?exon_id WHERE {
  ?transcript obo:SO_has_part ?exon .
  ?exon dc:identifier ?exon_id .
  ?transcript dc:identifier "ENST00000381223" .
}
];
@result = query($sparql);
cmp_ok(@result, '==', 2, 'Two exons also attached to a transcript without order');

# Test some xrefs

$sparql = qq[$prefixes
SELECT ?xref_label WHERE {
  ?gene term:DIRECT ?xref .
  ?xref a identifiers:hgnc .
  ?xref rdfs:label ?xref_label .
  ?gene dc:identifier "ENSG00000214717" .
}
];
@result = query($sparql);
# use Data::Dumper;
# note(Dumper @result);
is_deeply([map {$_->{xref_label}->value} @result],["ZBED1"], "HGNC xrefs are fetchable" );

$sparql = qq[$prefixes
SELECT ?gene_name WHERE {
  ?gene dc:identifier ?gene_name .
  ?gene a obo:SO_0001217 .
  ?gene ?predicate ?xref .
  ?xref rdfs:label ?xref_label .
} VALUES ?xref_label { "ZBED1" }
];
@result = query($sparql);
is($result[0]->{gene_name}->value, 'ENSG00000214717', "Xref vice versa");
# Can't do much more interesting testing without also loading the ontologies to help with inference.

done_testing;