use Modern::Perl;
use Test::More;

use Bio::EnsEMBL::RDF::EnsemblToTripleConverter;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Test::MultiTestDB;

my $test_db = Bio::EnsEMBL::Test::MultiTestDB->new('ontology' );
my $surplus_db = Bio::EnsEMBL::Test::MultiTestDB->new('homo_sapiens' );
my $dba = $test_db->get_DBAdaptor('ontology');
my $dbb = $surplus_db->get_DBAdaptor('core');
my $ontoa = $dba->get_OntologyTermAdaptor();
my $meta_adaptor = $dbb->get_MetaContainer();

my $fake_file;
my $fh;
ok ( open($fh,'>',\$fake_file) );
my $converter = Bio::EnsEMBL::RDF::EnsemblToTripleConverter->new($ontoa,$meta_adaptor,'homo_sapiens',$fh,82);
is ($converter->species,'homo_sapiens',"Constructor assignments");
is ($converter->release,'82',"Constructor assignments");

$converter->print_species_info();
note $fake_file;

close $fh;

# Compare output against "proper" RDF library.



done_testing;