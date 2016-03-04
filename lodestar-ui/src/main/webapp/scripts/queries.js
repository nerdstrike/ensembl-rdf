

/*
 * Copyright (c) 2016 EMBL - European Bioinformatics Institute
 * Licensed under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 * http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software distributed under the
 * License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
 * either express or implied. See the License for the specific language governing permissions
 * and limitations under the License.
 */

var exampleQueries = [

    {
        shortname : "Query 1",
        description: "Show all transcripts of human BRCA2 gene and their coordinates",
        query: "SELECT DISTINCT ?transcript ?id ?typeLabel ?reference ?begin ?end ?location { \n" +
               "  ?transcript obo:SO_transcribed_from ensembl:ENSG00000139618 ;\n" +
               "              a ?type;\n"+
               "              dc:identifier ?id .\n" +
               "  OPTIONAL {\n" +
               "    ?transcript faldo:location ?location .\n" +
               "    ?location faldo:begin [faldo:position ?begin] .\n" +
               "    ?location faldo:end [faldo:position ?end ] .\n" +
               "    ?location faldo:reference ?reference .\n"+
               "  }\n"+ 
               "  OPTIONAL {?type rdfs:label ?typeLabel}\n"+
               "}"
    },
    {
        shortname : "Query 2",
        description: "Show ordered exons with their length for transcript ENST00000380152",
        query: "SELECT DISTINCT ?id ?order ?reference ?begin ?end ?strand {\n" +
               "  ensembltranscript:ENST00000380152 obo:SO_has_part ?exon;\n" +
               "                                    sio:SIO_000974 ?orderedPart .\n" +
               "  ?exon dc:identifier ?id .\n" +
               "  # we include an explicit exon order\n" +
               "  # so that we can order correctly in both + and - strand \n" +
               "  ?orderedPart sio:SIO_000628 ?exon .\n" +
               "  ?orderedPart sio:SIO_000300 ?order .\n\n" +
               "  OPTIONAL {\n" +
               "    ?exon faldo:location ?location .\n" +
               "    ?location faldo:begin\n" +
               "      [a ?strand ;\n" +
               "       faldo:position ?begin] .\n" +
               "    ?location faldo:end\n" +
               "      [a ?strand ;\n" +
               "       faldo:position ?end] .\n" +
               "  ?location faldo:reference ?reference .\n" +
               "  }\n" +
               "FILTER (?strand != faldo:ExactPosition)\n" +
               "}\n" +
               "ORDER BY ASC(?order)"
    },
    {
        shortname : "Query 3",
        description: "Get all mouse genes on chromosome 11 between location 101,100,523 and 101,190,725 forward strand",
        query:  "SELECT DISTINCT ?gene ?id ?label ?typelabel ?desc ?begin ?end {\n" +
                "  ?location faldo:begin\n" +
                "       [a faldo:ForwardStrandPosition ;\n" +
                "        faldo:position ?begin] .\n" +
                "  ?location faldo:end\n" +
                "       [a faldo:ForwardStrandPosition ;\n" +
                "        faldo:position ?end] .\n" +
                "  ?location faldo:reference <http://rdf.ebi.ac.uk/resource/ensembl/84/mus_musculus/GRCm38/11> .  \n" +
                "  ?gene a ?type ;\n" +
                "        rdfs:label ?label ;\n" +
                "        dc:description ?desc ;\n" +
                "        dc:identifier ?id ;\n" +
                "        faldo:location ?location .\n" +
                " FILTER (?begin >= 101100523 && ?end <= 101190725 )\n" +
                " OPTIONAL {?type rdfs:label ?typelabel}\n" +
                "}\n"
    },
    {
        shortname : "Query 4",
        description: "Get orthologs for human gene ENSG00000139618",
        query:  "SELECT DISTINCT ?gene ?ortholog ?orthologLabel ?name {\n" +
                " ?gene sio:SIO_000558 ?ortholog .\n" +
                " ?gene obo:RO_0002162 ?taxon .\n" +
                " ?gene rdfs:label ?geneLabel .\n" +
                " ?ortholog rdfs:label ?orthologLabel .\n" +
                " ?ortholog obo:RO_0002162 ?ortholog_taxon .\n" +
                " ?ortholog_taxon skos:altLabel ?name\n" +
                " VALUES ?gene {ensembl:ENSG00000139618} \n" +
                " FILTER (?taxon != ?ortholog_taxon) \n" +
                "}\n"
    },
    {
        shortname : "Do it like Biomart Query 1",
        description: "Get all exons for a given list of transcripts",
        query: "SELECT ?transcript ?exon ?id ?order ?begin ?end ?strand{\n" +
               "  ?transcript obo:SO_has_part ?exon;\n" +
               "              sio:SIO_000974 ?orderedPart .\n" +
               "  ?exon dc:identifier ?id .\n" +
               "  ?orderedPart sio:SIO_000628 ?exon .\n" +
               "  ?orderedPart sio:SIO_000300 ?order .\n" +
               "  OPTIONAL {\n" +
               "   ?exon faldo:location ?location .\n" +
               "   ?location faldo:begin ?startthing .\n" +
               "   ?startthing faldo:position ?begin .\n" +
               "   ?startthing a ?strand .\n" +
               "   ?location faldo:end ?endthing .\n" +
               "   ?endthing faldo:position ?end .\n" +
               " }\n" +
               " VALUES ?transcript { ensembltranscript:ENST00000380152 ensembltranscript:ENST00000408937 ensembltranscript:ENST00000403559 ensembltranscript:ENST00000393494 ensembltranscript:ENST00000350908} \n" +
               "}\n" +
               "ORDER BY ?id ?order"
    },
    {
        shortname : "Do it like Biomart Query 2",
        description: "Find all non-Ensembl references for features that have EMBL references",
        query: "SELECT ?feature ?dbentry ?other_dbentry ?property WHERE { \n" +
               "  ?feature ?property ?dbentry .\n" +
               "  ?dbentry rdf:type <http://rdf.ebi.ac.uk/terms/ensembl/EMBL> .\n" +
               "  ?property rdfs:subPropertyOf* skos:related .\n" +
               "\n" +
               "  ?feature ?property2 ?other_dbentry .\n" +
               "  ?property2 rdfs:subPropertyOf* skos:related .\n" +
               "  FILTER ( ?dbentry != ?other_dbentry )\n" +
               "}\n" 
    },
    {
        shortname : "Do it like Biomart Query 3",
        description : "Retrieve a list of external references from accessions you know, e.g. Uniprot IDs to all related accessions",
        query: "SELECT DISTINCT ?feature ?dbentry ?property ?dbentry2 WHERE { \n" +
               "  ?feature ?property ?dbentry .\n" +
               "  ?property rdfs:subPropertyOf* skos:related .\n" +
               "  ?feature ?property2 ?dbentry2 .\n" +
               "  VALUES ?dbentry { <http://purl.uniprot.org/O15409> }\n" +
               "  FILTER ( ?dbentry != ?dbentry2 ) \n" +
               "}"
    },
    {
        shortname : "Do it like Biomart Query 4",
        description : "Get all features on a chromosome (NOTE: currently only genes, transcripts, exons and translations)",
        query: "SELECT ?feature ?region ?start ?end ?strand WHERE {\n" +
                   "?feature faldo:location ?region .\n" +
                   "?region faldo:begin ?start .\n" +
                   "?start faldo:position ?start_value .\n" +
                   "?start rdf:type ?strand .\n" +
                   "?region faldo:end ?end .\n" +
                   "?end faldo:position ?end_value .\n" +
                   "?region faldo:reference ?seqregion .\n" +
                   "VALUES ?seqregion { <http://rdf.ebi.ac.uk/resource/ensembl/83/homo_sapiens/GRCh38/20> }\n" +
                   "FILTER ( ?strand = faldo:ForwardStrandPosition OR ?strand = faldo:ReverseStrandPosition )\n" +
                "}\n" +
                "LIMIT 200"
    },
    {
        shortname : "Do it like Biomart Query 5",
        description : "Get all protein-coding genes on a chromosome",
        query:  "SELECT ?feature ?name ?region ?place WHERE {\n" +
                "   ?feature rdf:type ?type .\n" +
                "   ?feature faldo:location ?region .\n" +
                "   ?region faldo:reference ?place .\n" +
                "   ?feature ?property ?dbref .\n" +
                "   ?property rdfs:subPropertyOf* skos:related .\n" +
                "   ?dbref rdfs:label ?name .\n" +
                "   FILTER ( ?type = enst:protein_coding )\n" +
                "   VALUES ?place { <http://rdf.ebi.ac.uk/resource/ensembl/83/homo_sapiens/GRCh38/20> }\n" +
                "}"
    },
    {
        shortname : "Federated query 1",
        description: "Get protein information from Uniprot that Ensembl has associated with ENSG00000139618 via a federated query",
        query:
                "SELECT ?xref ?uniprot_id ?uniprot_uri ?isoform ?seq {\n" +
                "  <http://rdf.ebi.ac.uk/resource/ensembl/ENSG00000128573> ensemblterms:DEPENDENT ?xref .\n" +
                   "?xref dc:identifier ?uniprot_id .\n" +
                   "BIND ( IRI(CONCAT('http://purl.uniprot.org/uniprot/',str(?uniprot_id) ) ) AS ?uniprot_uri )\n" +
                   "SERVICE <http://sparql.uniprot.org/sparql> {\n" +
                     "?uniprot_uri core:sequence ?isoform .\n" +
                     "?isoform rdf:value ?seq .\n" +
                "   }\n" +
                " }\n"
    },
    {
        shortname : "Federated query 2",
        description : "Use DisGeNet to acquire text-mined disease associations for Ensembl genes and associated external names",
        query : "SELECT DISTINCT ?ensemblg ?disease ?diseasename WHERE {\n" +
                "  GRAPH <http://rdf.ebi.ac.uk/dataset/ensembl/84/homo_sapiens> {\n" +
                "  ?ensemblg ensemblterms:DEPENDENT ?gene ;\n" +
                "            obo:RO_0002162 <http://identifiers.org/taxonomy/9606> .\n" +
                "  FILTER regex(str(?ensemblg), 'ensg', 'i')\n" +
                "  FILTER (?gene = <http://identifiers.org/ncbigene/675>)\n" +
                "  \n" +
                "  SERVICE <http://rdf.disgenet.org/sparql/> {\n" +
                "    ?gda sio:SIO_000628 ?gene, ?disease .\n" +
                "    ?disease a <http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl#C7057> ;\n" +
                "               dcterms:title ?diseasename .\n" +
                "  }\n  }\n}"
    }
]