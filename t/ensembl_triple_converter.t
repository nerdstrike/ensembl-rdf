use Modern::Perl;
use Test::More;

use Bio::EnsEMBL::RDF::EnsemblToTripleConverter;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Test::MultiTestDB;

use Bio::EnsEMBL::BulkFetcher;

use RDF::Trine;
use RDF::Query;

my $test_db = Bio::EnsEMBL::Test::MultiTestDB->new('ontology' );
my $surplus_db = Bio::EnsEMBL::Test::MultiTestDB->new('homo_sapiens' );
my $dba = $test_db->get_DBAdaptor('ontology');
my $dbb = $surplus_db->get_DBAdaptor('core');
my $ontoa = $dba->get_OntologyTermAdaptor();
my $meta_adaptor = $dbb->get_MetaContainer();

my $fake_file;
my $fh;
ok ( open($fh,'>',\$fake_file) );
my $converter = Bio::EnsEMBL::RDF::EnsemblToTripleConverter->new($ontoa,$meta_adaptor,'homo_sapiens',$fh,82,'../xref_LOD_mapping.json');
is ($converter->species,'homo_sapiens',"Constructor assignments");
is ($converter->release,'82',"Constructor assignments");

my $slice_adaptor = $dbb->get_SliceAdaptor();
my $slices = $slice_adaptor->fetch_all('chromosome');
$converter->print_namespaces();
$converter->print_species_info();
$converter->print_seq_regions($slices);

my $fetcher = Bio::EnsEMBL::BulkFetcher->new();
# These are NOT proper Gene objects, they are hash summaries.
my $genes = $fetcher->export_genes($dbb);
my ($gene) = grep { $_->{id} eq 'ENSG00000214717'} @$genes;

$converter->print_feature($gene, 'http://rdf.ebi.ac.uk/resource/ensembl/'.$gene->{id}, 'gene');


close $fh;
print $fake_file."\n\n";
# Compare output against "proper" RDF library.
my $store = RDF::Trine::Store::Memory->new();
my $model = RDF::Trine::Model->new($store);
my $parser = RDF::Trine::Parser->new('turtle');

$parser->parse_into_model('http://rdf.ebi.ac.uk/resource/ensembl/', $fake_file, $model);

# Test seq region labels
my $sparql = "
PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?label WHERE {
  ?seq_region rdfs:subClassOf obo:SO_0000340 .
  ?seq_region rdfs:label ?label .
}";
my @result = query($sparql);
my @strings = map { $_->{label}->as_string } @result; 

is_deeply(\@strings, ['"Homo sapiens chromosome chromosome:GRCh38:6:1:170805979:1"','"Homo sapiens chromosome chromosome:GRCh38:Y:1:57227415:1"','"Homo sapiens chromosome chromosome:GRCh38:X:1:156040895:1"'], 'Seq regions returned with correct labels');

# Test gene
$sparql = qq[
PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX dc: <http://purl.org/dc/elements/1.1/>
PREFIX faldo: <http://biohackathon.org/resource/faldo#>
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

sub query {
  my $sparql = shift;
  my $query = RDF::Query->new($sparql) || die RDF::Query->error;
  @result = $query->execute($model);
  return @result;
}


done_testing;