# Correlates Ensembl IDs (and later on, xrefs) with PubMed beta Sparql endpoint

use Modern::Perl;
use LWP::UserAgent;
use JSON;
use URI::Escape;
use RDF::Query::Client;
use Bio::EnsEMBL::Registry;
use Time::HiRes qw/gettimeofday tv_interval/;

my $uri = 'http://wwwdev.ebi.ac.uk/rdf/services/textmining/sparql';
# my $content_type = 'x-www-form-urlencoded';
# my $accept = 'application/sparql-results+json';

my $lwp = LWP::UserAgent->new();
$lwp->agent('ensembl-xref  (Linux, perl/5.14.2)');

Bio::EnsEMBL::Registry->load_registry_from_db(
  -host => 'mysql-ensembl-mirror.ebi.ac.uk',
  -user => 'anonymous',
  -port => 4240,
  # -host => 'asiadb.ensembl.org',
  # -user => 'anonymous',
  # -port => 5306,
  -db_version => 81,
  );
print "Connected to Ensembl";

my $sparql_start = 'PREFIX dcterms: <http://purl.org/dc/terms/>
PREFIX oa: <http://www.w3.org/ns/oa#>

SELECT ?prefix ?exact ?postfix ?section ?source WHERE {
?annotation oa:hasBody <http://identifiers.org/ensembl/';

my $sparql_end = '>.
?annotation oa:hasTarget ?target.
?target oa:hasSource ?source.
?target oa:hasSelector ?selector.
?target dcterms:isPartOf ?section.
?selector oa:prefix ?prefix.
?selector oa:exact ?exact.
?selector oa:postfix ?postfix.
}';

my $gene_adaptor = Bio::EnsEMBL::Registry->get_adaptor('Human','core','Gene');
my $genes =  $gene_adaptor->fetch_all();
my $sparql;

my $hits = 0;
print "Querying Pubmed beta\n"; 

my $start_time = [gettimeofday()];
while ( my $gene = shift @$genes) {
  $sparql = $sparql_start . $gene->stable_id . $sparql_end;
  my $query = RDF::Query::Client->new($sparql, {UserAgent => $lwp});
  my @results = $query->execute($uri);
  use Data::Dumper;
  while (my $row = shift @results) {
    print Dumper $row;
    print $row->{source}->as_string."\n";
  }
  $hits++;
}
my $elapsed = tv_interval ( $start_time, [gettimeofday()]);
printf "Total of %s Ensembl genes found in Pubmed beta\n",$hits;
printf "Total time is %.2f seconds\n",$elapsed;
print "Finished\n";
