#!/usr/bin/env perl

=head1 LICENSE

Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 NAME

    ensembl2ttl - Convert Ensembl core data to RDF turtle

=head1 AUTHOR

Will McLaren, Simon Jupp, European Bioinformatics Institute

=head1 SYNOPSIS
    ensembl2ttl [options]
     Options:
       -species         The common name for species to conver e.g. Human
       -version         The Ensembl version e.g. 75 
       -help            brief help message
       -man             full documentation

=head1 OPTIONS

=over 8

=item B<-species>

       The common name for species to conver e.g. Human

=item B<-version>

       The Ensembl version e.g. 75

=item B<-help>

    Print a brief help message and exits.

=item B<-man>

    Prints the manual page and exits.

=back

=head1 DESCRIPTION

    Script to dump Ensembl Variation triples.

    Requires installation of Ensembl Core, Variation and Regulation APIs, as well as dependencies such as BioPerl

=cut


use strict;

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use URI::Escape;
use JSON;
use LWP::UserAgent;
use Digest::MD5 qw(md5_hex);

my $species = '';
my $version = '';
my $path;
my $split;
my $virtgraph;
my $man = 0;
my $limit;
my $help = 0;
#"ensembldb.ensembl.org";
my $host = "mysql-ensembl-mirror.ebi.ac.uk"; 
my $port = "4240";
my $user = "anonymous";
my $genome = "";
my $zooma = 'http://www.ebi.ac.uk/fgpt/zooma/v2/api';

GetOptions (
    'species=s' => \$species,
    'version=s' => \$version,
    'virtgraph' => \$virtgraph,
    'out=s' => \$path,
    'split=i' => \$split,
    'limit=i' => \$limit,
    'host=s' => \$host,
    'port=i' => \$port,
    'user=s' => \$user,
    'genome=s' => \$genome,
    'help|?' => \$help,
    'zooma=s' => \$zooma,
    man => \$man
    ) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;

if (!$species || !$version) {
    pod2usage(1);
}
print STDOUT "Using Ensembl variation DB $species version $version\n";

my $outfile = ${species}.'_'.${version}.'_variation.ttl.gz';
if ($path) {
    $outfile = $path."/".$outfile;
}

# create the output file
open OUT, " | gzip -c >$outfile" || die "Can't open out file $outfile\n";

# common prefixes used
my %prefix = (
  ensembl => 'http://rdf.ebi.ac.uk/resource/ensembl/',
  ensemblvariation => 'http://rdf.ebi.ac.uk/terms/ensemblvariation/',
  transcript => 'http://rdf.ebi.ac.uk/resource/ensembl.transcript/',
  ensembl_variant => 'http://rdf.ebi.ac.uk/resource/ensembl.variant/',
  protein => 'http://rdf.ebi.ac.uk/resource/ensembl.protein/',
  exon => 'http://rdf.ebi.ac.uk/resource/ensembl.exon/',
  term => 'http://rdf.ebi.ac.uk/terms/ensembl/',
  rdfs => 'http://www.w3.org/2000/01/rdf-schema#',
  sio => 'http://semanticscience.org/resource/',
  dc => 'http://purl.org/dc/terms/',
  rdf => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
  faldo => 'http://biohackathon.org/resource/faldo#',
  obo => 'http://purl.obolibrary.org/obo/',
  skos => 'http://www.w3.org/2004/02/skos/core#',
  identifiers => 'http://identifiers.org/',
  taxon => 'http://identifiers.org/taxonomy/',
  oban => 'http://purl.org/oban/'
);

# create a map of prefixes for easy lookup
foreach (keys %prefix) {
  triple('@prefix',$_.':',u($prefix{$_}) );
}

Bio::EnsEMBL::Registry->set_reconnect_when_lost(1);

# Choice of database host is a factor in how fast the script runs. Try to find your nearest mirror, and check the database version before running.
Bio::EnsEMBL::Registry->load_registry_from_db(
  -host => $host,
#  -host => 'ensembldb.ensembl.org',
  -user => $user,
  -port => $port,
  -db_version => $version,
);

# Get all db adaptors
my $va = Bio::EnsEMBL::Registry->get_adaptor($species,'Variation','Variation');
my $pfa = Bio::EnsEMBL::Registry->get_adaptor($species,'Variation','PhenotypeFeature');

my $ontoa = Bio::EnsEMBL::Registry->get_adaptor( 'Multi', 'Ontology', 'OntologyTerm' );

my $db_entry_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $species, 'Core', 'DBEntry' );

my $meta = Bio::EnsEMBL::Registry->get_adaptor($species,'Core','MetaContainer');

# create a lookup table for term to ontology id
my %term2ontologyId;

# simple count for testing
my $count = 0;


# create a map of taxon id to species name, we will create some triples for these at the end

# get the taxon id for this species 
my $taxon_id = $meta->get_taxonomy_id;
my $scientific_name = $meta->get_scientific_name;
my $common_name = $meta->get_common_name;

# print out global triples about the organism  
triple('taxon:'.$taxon_id, 'rdfs:subClassOf', 'obo:OBI_0100026');
triple('taxon:'.$taxon_id, 'rdfs:label', '"'.$scientific_name.'"');
triple('taxon:'.$taxon_id, 'skos:altLabel', '"'.$common_name.'"');
triple('taxon:'.$taxon_id, 'dc:identifier', '"'.$taxon_id.'"');

# get the current ensembl release number 
my $schemaVersion = $meta->get_schema_version;

# check if we want to create a virtuoso graph file for this output file
if ($virtgraph) {
  my $versionGraphUri = "http://rdf.ebi.ac.uk/dataset/ensembl/".$version;
  my $graphUri = $versionGraphUri."/".$taxon_id;
  my $graphFile = $outfile.'.graph';
  open GRAPH, ">$graphFile" || die "Can't create the virtuoso graph file\n";
  print GRAPH $graphUri;
  close GRAPH;
  # make the species graph a subgraph of the version graph
  triple (u($graphUri), '<http://www.w3.org/2004/03/trix/rdfg-1/subGraphOf>', u($versionGraphUri)); 
}

my $nspace = 'ensembl_variant';
my $vpo = 'ensemblvariation';

my $http = LWP::UserAgent->new();
$http->default_header( 'ContentType' => 'application/json' );


# find the max variation ID
my $sth = $va->db->dbc->prepare(qq{SELECT max(variation_id) FROM variation});
$sth->execute();

my $max_id;
$sth->bind_col(1, \$max_id);
$sth->fetch();
$sth->finish();

my $batch_size = 100;
my $from_id = 1;

while($from_id <= $max_id) {
  my $to_id = $from_id + ($batch_size - 1);

  print "Dumping $from_id to $to_id\n";

  my $vi = $va->fetch_Iterator_by_dbID_list([$from_id..$to_id]);
  $from_id += $batch_size;
# open IN, 'BRCA2_variation_ids.txt';
# my @ids;
# my $batch_size = 100;
#
# while(<IN>) {
#   chomp;
#   push @ids, $_ if /^\d+$/;
# }
#
# my $vi = $va->fetch_Iterator_by_dbID_list(\@ids);

  while(my $v = $vi->next()) {
    $count++;
    # last if $count > 1;
  
    my $vfs = $v->get_all_VariationFeatures;
    my $first_vf = shift @{$vfs};
    
    next unless $first_vf;
  
    my $vname = $v->name;
    my $vf_subj = "$nspace:".uri_escape($vname);
  
    # dump names for the variant
    triple($vf_subj, 'rdfs:label', l($vname));
    triple($vf_subj, 'skos:altLabel', l($_)) for @{$v->get_all_synonyms};

    # get SO class
    my $class = $first_vf->class_SO_term;
    my $ontoTypeId = getSOOntologyId($class);
    if ($ontoTypeId) {
      triple($vf_subj, 'a', $ontoTypeId);
    }
    # triple($vf_subj, 'a', 'term:'.$class);

    # add source, clinical significance
    triple($vf_subj, "$vpo:has_source", l($v->source));
    triple($vf_subj, "$vpo:has_clinical_significance", l($_)) for @{$v->get_all_clinical_significance_states};


    # add alleles
    my $ac = 0;

    foreach my $allele(split '/', $first_vf->allele_string) {
      
      # probably define this allele as a subject
      # then we can assign more properties to it
      # reference, ancestral, minor?
      my $allele_subj = $prefix{$nspace}.$vname.'#'.replace_whitespace($allele);
  
      triple($vf_subj, "$vpo:has_allele", u($allele_subj));
  
      triple(u($allele_subj), 'rdfs:label', l("$vname allele $allele"));
  
      # is reference?
      if($ac == 0) {
        triple(u($allele_subj), "a", "$vpo:reference_allele", );
      }
  
      # is ancestral?
      if($v->ancestral_allele eq $allele) {
        triple(u($allele_subj), "a", "$vpo:ancestral_allele");
      }
      else {
        triple(u($allele_subj), "a", "$vpo:derived_allele");
      }
  
      # is minor?
      if($v->minor_allele eq $allele) {
        triple(u($allele_subj), "a", "$vpo:minor_allele");
      }
  
      # alleles also have a location since VFs can have more than one location
  
      $ac++;
    }

    foreach my $vf(@{$v->get_all_VariationFeatures}) {
  
      dump_feature($vf, $nspace, $vname);
  
      # get transcript variations
      foreach my $tv(@{$vf->get_all_TranscriptVariations}) {
      
        # skip upstream/downstream ones for now
        next unless $tv->cdna_start;
    
        # then get the specific transcript variation allele objects
        # these are linked back to the variation feature object via the allele object
        # created above
        foreach my $tva(@{$tv->get_all_alternate_TranscriptVariationAlleles}) {
          my $allele = uri_escape($tva->variation_feature_seq);
          my $allele_subj = $nspace.':'.$vname.'#'.$allele;
      
          my $tva_subj = $nspace.':'.$tv->transcript->stable_id.'_'.$vname.'#'.$allele;
          
          # $DB::single = 1;
      
          # link the allele to the tva
          triple($allele_subj, "$vpo:has_variant_effect", $tva_subj);
        
          # link the transcript to the tva
          triple($tva_subj, 'obo:so_overlaps', 'transcript:'.$tv->transcript->stable_id);
      
          # consequence types
          foreach my $csq(map {$_->SO_term} @{$tva->get_all_OverlapConsequences}) {
  
            # get SO class
            my $ontoTypeId = getSOOntologyId($csq);
            if ($ontoTypeId) {
              triple($tva_subj, 'a', $ontoTypeId);
            }
            # triple($tva_subj, 'a', 'term:'.$csq);
          }
      
          # HGVS names
          triple($tva_subj, "$vpo:has_HGVS_transcript_name", l($tva->hgvs_transcript)) if $tva->{hgvs_transcript};
          triple($tva_subj, "$vpo:has_HGVS_protein_name", l($tva->hgvs_protein)) if $tva->{hgvs_protein};
      
          # SIFT, PolyPhen
          foreach my $tool(qw(SIFT PolyPhen)) {
            my $pred_method = lc($tool).'_prediction';
            my $score_method = lc($tool).'_score';
        
            if($tva->$pred_method) {
              triple($tva_subj, "$vpo:has_$tool\_prediction", l($tva->$pred_method));
              triple($tva_subj, "$vpo:has_$tool\_prediction", l($tva->$score_method).'^^xsd:float');
            }
          }
      
          # amino acids
          if(my $pep = $tva->pep_allele_string) {
            my ($r, $a) = split '/', $pep;
            triple($tva_subj, "$vpo:has_reference_peptide_sequence", l($r));
            triple($tva_subj, "$vpo:has_alternate_peptide_sequence", l($a)) if $a;
          }
        }
      }
    }

    # get phenotypes
    foreach my $pf(@{$pfa->fetch_all_by_Variation($v)}) {

      my $phen = $pf->phenotype;
      my $desc = $phen->description;
      my $match;
      
      # try and match to a term from zooma
      # my $content = $response->decoded_content;
      # if(length $content) {
      #   my $hash = decode_json($content);
      #
      #   my $best_score = 0;
      #   my $best_count = 0;
      #
      #   foreach my $res(@{$hash->{result}}) {
      #     if($res->{score} > $best_score) {
      #       $best_score = $res->{score};
      #       $best_count = 1;
      #     }
      #     elsif($res->{score} == $best_score) {
      #       $best_count++;
      #     }
      #   }
      #
      #   if($best_count == 1) {
      #     my ($result) = grep {$_->{score} == $best_score} @{$hash->{result}};
      #
      #     $match = (split(/\s+/, $result->{notable}->{name}))[-1];
      #   }
      # }

      # create an association subbject
      my $pf_subj = $nspace.':'.md5_hex($vname.$desc);
      
      triple($pf_subj, 'typeof', 'oban:association');
      triple($pf_subj, 'oban:association_has_object_name', l($desc));
      triple($pf_subj, 'oban:association_has_subject', $vf_subj);
      
      # triple($vf_subj, "oban:association", l($desc));
    }
  }
}

print "Dumped triples for $count variants \n";

my %reference_hash;

sub dump_identifers_mapping {

  my $feature = shift;
  my $namespace = shift;
  my $db = 'ensembl';
  if ($genome) {
    $db = $db.'.'.$genome;
  }
  triple($namespace.":".$feature->stable_id(), 'rdfs:seeAlso', u($prefix{identifiers}.$db.'/'.$feature->stable_id()));
	  
}

sub dump_feature {
  my $feature = shift;
  my $namespace = shift;
  my $stable_id = shift;
  if (!$stable_id) {
    $stable_id = $feature->stable_id;
  }

  my $slice = $feature->slice;
  my $region_name = $slice->seq_region_name;
  my $cs = $slice->coord_system;
        
  # generate a version specific portion of a URL that includes the database version, species, assembly version and region name
  # e.g. The URI for human chromosme 1 in assembly GRCh37 would be http://rdf.ebi.ac.uk/resource/ensembl/75/GRCh37/1
  my $version_url = $prefix{ensembl}.$schemaVersion.'/'.$cs->name.':'.$cs->version.':'.$feature->seq_region_name; 

  # we also create a non versioned URI that is a super class e.g. 
  # http://rdf.ebi.ac.uk/resource/ensembl/homo_sapiens/1
  my $non_version_url = $prefix{ensembl}.$taxon_id.'/'.$cs->name.':'.$feature->seq_region_name; 

  # these are typed as chromosome or patches e.g. HG991_PATCH
  my $reference = u($version_url);
  if (! $reference_hash{$reference}) {
    triple($reference, 'rdfs:subClassOf', u($non_version_url));
    if ($cs->name eq 'chromosome') {	
      triple(u($non_version_url), 'rdfs:subClassOf', 'obo:SO_0000340');
    }
    else {
      triple(u($non_version_url), 'rdfs:subClassOf', 'term:'.$cs->name);
      triple('term:'.$cs->name, 'rdfs:subClassOf', 'term:EnsemblRegion');
    }
    triple(u($non_version_url), 'rdfs:label', '"'.${common_name}.' '.$cs->name.' '.$feature->seq_region_name.'"');	
    triple($reference, 'rdfs:label', '"'.${common_name}.' '.$cs->name.' '.$feature->seq_region_name.' ('.$cs->version.')"');	
    triple($reference, 'dc:identifier', '"'.$feature->seq_region_name.'"');	
    triple($reference, 'term:inEnsemblSchemaNumber', '"'.$schemaVersion.'"');	
    triple($reference, 'term:inEnsemblAssembly', '"'.$cs->version.'"');	
	
    # add mapping to INSDC and RefSeq
    my @alternative_names = ( @{$slice->get_all_synonyms('INSDC')}, @{$slice->get_all_synonyms('RefSeq_genomic')});
    for my $syn (@alternative_names) {
      my $exdbname = $db_entry_adaptor->get_db_name_from_external_db_id($syn->external_db_id);
      my $id = $syn->name;
      my $featureUri;
      if ($exdbname =~/insdc/i) {
        $featureUri = $prefix{identifiers}.'insdc/'.$id;
      }
      else {
        $featureUri = $prefix{identifiers}.'refseq/'.$id;
      }
      triple(u($featureUri), 'dc:identifier', '"'.$id.'"');
      triple($reference, 'sio:equivalentTo', u($featureUri));	
    }
	
    taxonTriple($reference);
    taxonTriple(u($non_version_url));

    $reference_hash{$reference} = 1;
  }

  # implement the FALDO model:  A semantic standard for describing the location of nucleotide and protein feature annotation
  # dx.doi.org/10.1101/002121
  my $begin = ($feature->strand >= 0) ? $feature->start : $feature->end;
  my $end = ($feature->strand >= 0) ? $feature->end : $feature->start;
  my $location = u($version_url.':'.$feature->start.'-'.$feature->end.':'.$feature->strand);
  my $beginUri = u($version_url.':'.$begin.':'.$feature->strand);
  my $endUri = u($version_url.':'.$end.':'.$feature->strand);
  triple($namespace.':'.$stable_id, 'faldo:location', $location);
  triple($location, 'rdfs:label', '"'.$cs->name.' '.$feature->seq_region_name.':'.$feature->end.'-'.$feature->end.':'.$feature->strand.'"');
  triple($location, 'rdf:type', 'faldo:Region');
  triple($location, 'faldo:begin', $beginUri);
  triple($location, 'faldo:end', $endUri);
  triple($location, 'faldo:reference', $reference);
  triple($beginUri, 'rdf:type', 'faldo:ExactPosition');
  triple($beginUri, 'rdf:type', ($feature->strand >= 0)? 'faldo:ForwardStrandPosition':'faldo:ReverseStrandPosition');
  #    triple($beginUri, 'faldo:position', ($feature->strand == 1) ? $feature->start : $feature->end);
  triple($beginUri, 'faldo:position', $begin);
  triple($beginUri, 'faldo:reference', $reference);

  triple($endUri, 'rdf:type', 'faldo:ExactPosition');
  triple($endUri, 'rdf:type', ($feature->strand >= 0)? 'faldo:ForwardStrandPosition':'faldo:ReverseStrandPosition');
  #    triple($endUri, 'faldo:position', ($feature->strand == 1) ? $feature->end : $feature->start);
  triple($endUri, 'faldo:position', $end);
  triple($endUri, 'faldo:reference', $reference);

  triple($namespace.':'.$stable_id, 'dc:identifier', '"'.$stable_id.'"' );
}


sub u {
  return '<'.$_[0].'>';
}

sub l {
  return '"'.escape($_[0]).'"';
}

sub replace_whitespace {
    my $string = shift;
    $string =~ s/\s+/_/;
    return $string;
}

sub triple {
  printf OUT "%s %s %s .\n", @_;
}

sub taxonTriple {
  triple($_[0], 'obo:RO_0002162', 'taxon:'.$taxon_id);
}

sub getSOOntologyId {
  my $term = shift;
  if ($term2ontologyId{$term}) {
    return $term2ontologyId{$term};
  }
    
  my ($typeterm) =
  @{ $ontoa->fetch_all_by_name( $term, 'SO' ) };
    
  if (!$typeterm) {
	
    print STDERR "WARN: Can't find SO term for $term\n";
    $term2ontologyId{$term} =1; 
    # make the biotype a child of an ensembl biotype
    #triple($term2ontologyId{$term}, 'rdfs:subClassOf', 'term:EnsemblFeature');
    return undef;
  }
    
  my $id = $typeterm->accession;
  $id=~s/SO:/obo:SO_/;
  $term2ontologyId{$term} = $id;

  # make the biotype a child of an ensmebl biotype
  # triple($term2ontologyId{$term}, 'rdfs:subClassOf', 'term:EnsemblFeature');
 
  return $term2ontologyId{$term};
    
}

sub dumpVirtuoso {


}

sub escape {
  my $string = shift;
  $string =~s/(["])/\\$1/g;
  return $string;
}


close OUT;
