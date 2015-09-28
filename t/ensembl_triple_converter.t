use Modern::Perl;
use Test::More;

use Bio::EnsEMBL::RDF::EnsemblToTripleConverter;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Test::MultiTestDB;
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
close $fh;

# Compare output against "proper" RDF library.
my $store = RDF::Trine::Store::Memory->new();
my $model = RDF::Trine::Model->new($store);
my $parser = RDF::Trine::Parser->new('turtle');

$parser->parse_into_model('http://rdf.ebi.ac.uk/resource/ensembl/', $fake_file, $model);


my $query = RDF::Query->new("
PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?s ?p ?o WHERE {
  ?s ?p ?o .
}",{base_uri => 'http://rdf.ebi.ac.uk/resource/ensembl/'}
) || die RDF::Query->error;
my $iterator = $query->execute($model);
while (my $response = $iterator->next) {
  note $response->as_string;
}

$query = RDF::Query->new("
PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?label WHERE {
  ?seq_region rdfs:subClassOf obo:SO_0000340 .
  ?seq_region rdfs:label ?label .
}",{base_uri => 'http://rdf.ebi.ac.uk/resource/ensembl/'}
);


done_testing;