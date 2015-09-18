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
use IO::File;
my $debug;
my $uri = 'http://wwwdev.ebi.ac.uk/rdf/services/textmining/sparql';
# my $content_type = 'x-www-form-urlencoded';
# my $accept = 'application/sparql-results+json';

my $filename = shift;
$filename ||= 'hits_uris.txt';

my $lwp = LWP::UserAgent->new();
$lwp->agent('ensembl-xref (Linux, perl/5.14.2)');

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
my $fh = IO::File->new('hits_uris.txt','w');
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
my $e_progress = 0;
my $pub_progress = 0;

my $start_time = [gettimeofday()];
while ( my $gene = shift @$genes) {
  my @xrefs = @{ $gene->get_all_DBLinks };
  my @xref_names;
  foreach my $xref (@xrefs) {
    my $mapping = $converter->get_mapping($xref->dbname);
    if (exists $mapping->{canonical_LOD} && ! exists $mapping->{ignore}) {
      push @xref_names,$mapping->{canonical_LOD}.$xref->display_id;
    } # Some external DB names don't map to LOD URIs.
  }
  if (@xref_names > 0) {
    my $sparql_values = sprintf 'VALUES ?xref {%s}',join(' ', map { qq{<$_>}} @xref_names);
    $sparql = $sparql_prefix . $sparql_start . $sparql_values . $sparql_end;
    if ($debug) {print "DEBUG: $sparql"}
    my $query = RDF::Query::Client->new($sparql, {UserAgent => $lwp});
    my @results = $query->execute($uri);
    if (!$query->error) {
      while (my $row = shift @results) {
        $hits++;
        print $row->{source}->as_string."\n";
        push @lits,$row->{source}->as_string;
        $pub_progress++;
        if ($pub_progress % 100 == 0) {
          print "Found $pub_progress PubMed entries\n";
          while (my $string = shift @lits) {
            print $fh $string."\n";
          }
        }
      }
    } else {
      die "Error from Pubmed SPARQL server: ".$query->error."\n Data: $sparql, ".$gene->stable_id;
    }
    $e_progress++;
    if ($e_progress % 100 == 0) {
      print "Processed $e_progress Ensembl IDs\n";
    }
  }
  
  
}
my $elapsed = tv_interval ( $start_time, [gettimeofday()]);
# print join "\n",@lits;
while (my $string = shift @lits) {
  print $fh $string."\n";
}
$fh->close;

printf "\nTotal of %s Ensembl genes found in Pubmed beta\n",$hits;
printf "Total time is %.2f seconds\n",$elapsed;
printf "Matched %d PubMed articles\n",@lits;
print "Finished\n";
