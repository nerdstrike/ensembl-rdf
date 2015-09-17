# Correlates Ensembl IDs (and later on, xrefs) with PubMed beta Sparql endpoint

use Modern::Perl;
use LWP::UserAgent;
use JSON;
use URI::Escape;
use RDF::Query::Client;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::RDF::RDFlib;
use Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings;
use Time::HiRes qw/gettimeofday tv_interval/;

my $uri = 'http://wwwdev.ebi.ac.uk/rdf/services/textmining/sparql';
# my $content_type = 'x-www-form-urlencoded';
# my $accept = 'application/sparql-results+json';

my $lwp = LWP::UserAgent->new();
$lwp->agent('ensembl-xref  (Linux, perl/5.14.2)');

Bio::EnsEMBL::Registry->load_registry_from_db(
  # -host => 'mysql-ensembl-mirror.ebi.ac.uk',
  # -user => 'anonymous',
  # -port => 4240,
  -host => 'asiadb.ensembl.org',
  -user => 'anonymous',
  -port => 5306,
  -db_version => 81,
  );
print "Connected to Ensembl";

my $converter = Bio::EnsEMBL::RDF::EnsemblToIdentifierMappings->new('../xref_LOD_mapping.json');

my $sparql_prefix = compatible_name_spaces();

my $sparql_start = '
SELECT ?prefix ?exact ?postfix ?section ?source WHERE {
  ?annotation oa:hasBody ?xref .
  ?annotation oa:hasTarget ?target .
  ?target oa:hasSource ?source .
  ?target oa:hasSelector ?selector .
  ?target dcterms:isPartOf ?section .
  ?selector oa:prefix ?prefix .
  ?selector oa:exact ?exact .
  ?selector oa:postfix ?postfix .
';
my $sparql_end = '}';
my $gene_adaptor = Bio::EnsEMBL::Registry->get_adaptor('Human','core','Gene');
my $genes =  $gene_adaptor->fetch_all();
my $sparql;

my $hits = 0;
my @lits;
print "Querying Pubmed beta\n"; 
  use Data::Dumper;

my $start_time = [gettimeofday()];
while ( my $gene = shift @$genes) {
  my @xrefs = @{ $gene->get_all_DBLinks };
  my @xref_names;
  foreach my $xref (@xrefs) {
    my $mapping = $converter->get_mapping($xref->dbname);
    if (exists $mapping->{canonical_LOD} && ! exists $mapping->{ignore}) {
      push @xref_names,$mapping->{canonical_LOD}.$xref->display_id;
    } else {
      print "No mapping found for ".$xref->dbname."\n";
    }
  }
  if (@xref_names > 0) {
    my $sparql_values = sprintf 'VALUES ?xref {%s}'.join ' ', map { qq{$_}} @xref_names;
    $sparql = $sparql_prefix . $sparql_start . $sparql_values . $sparql_end;
    my $query = RDF::Query::Client->new($sparql, {UserAgent => $lwp});
    my @results = $query->execute($uri);
    while (my $row = shift @results) {
      print $row->{source}->as_string."\n";
      push @lits,$row->{source}->as_string;
    }
    $hits++;
  }
  
  last if $hits == 50;
}
my $elapsed = tv_interval ( $start_time, [gettimeofday()]);
print join "\n",@lits;
printf "\nTotal of %s Ensembl genes found in Pubmed beta\n",$hits;
printf "Total time is %.2f seconds\n",$elapsed;
printf "Matched %d PubMed articles\n",@lits;
print "Finished\n";
