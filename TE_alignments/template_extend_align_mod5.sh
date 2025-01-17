#!/bin/bash
#SBATCH --job-name=extract_hits
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=nocona
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem-per-cpu=60G
#SBATCH --mail-user nicole.paulat@ttu.edu

#### BASICS
# This script will take in queries generated by RepeatModeler and generate
# extended consensus sequences for visualization and evaluation using a combination of
# the Ray lab's extract_align python script and Robert Hubley's extension perl script. It is
# designed to allow for a triage of extended RepeatModeler output when generating de novo curated
# TE libraries from RepeatModeler output.
# 
# The output you're going to be most interested in will be in the images_and_alignments directory.

#### USAGE and OUTPUT
#
# Replace <NAME> in line 2 with your chosen job ID.
#
# sbatch scriptname.sh <TAXON> <FULL path to genome.gz> <FULL path to output directory> <FULL path to repeatmodeler queries>
#
# Input #1 = path to a genome file, zipped. The first field of the filename, as divided by ".", will end up as SUBNAME as a designation 
# Input #2 = the path to the output directory 
# Input #3 = path to a file with repeatmodeler consensuses with headers modified to remove "#" and "/" 
# 
# Example - sbatch /lustre/scratch/npaulat/yin_yang/ext_align/template_extend_align_npaulat.sh /lustre/scratch/npaulat/yin_yang/non_mamm_assemblies/LacAgi_GCA_009819535.1_pri_genomic.fna.gz /lustre/scratch/npaulat/yin_yang/ext_align /lustre/scratch/npaulat/yin_yang/te_fastas/nMariner1_Lbo.fa
#
## Output by directory (extend_align/SUBNAME...):
# blastfiles = blast output, database, and queries file
# extendlogs = log files from Hubley extension tool
# extensionwork = directory for each TE evaluated with output from tool
# extract_align = output from extract_align.py, contains catTEfiles to be used by extension tool
# genomefiles = genome assembly in .fa and .2bit format
# images_and_alignments = .png files and aligned files for visual validation 
# rejects = alignments filtered for too few hits

#### CONDA OPERATING ENVIRONMENT
#Set up conda environment if necessary before starting
#Note: Before using this script, I set up this working enviroment within conda using:
# $ conda create --name extend_env
# $ conda activate extend_env
# $ conda install biopython
# $ conda install pandas
# $ conda install -c bioconda pyfaidx
# $ conda install --channel bioconda pybedtools

#### STUFF THAT MAY NEED CHANGING -- CHECK ALL PATHS, ETC

#activate conda environment, load modules
. ~/conda/etc/profile.d/conda.sh
#conda activate extend_env
conda activate /home/npaulat/conda/envs/extend_env2
#module load gcc/9.2.0 bedtools2/2.29.2
module purge
module --ignore-cache load gcc/10.1.0 bedtools2/2.29.2

#Locations of critical software
SOFTWARE=/lustre/work/daray/software
EXTENDPATH=$SOFTWARE/RepeatModeler-dev/util
GITPATH=/home/daray/gitrepositories/bioinfo_tools

#Variables for extract_align.py
SEQBUFFER=100
SEQNUMBER=50
FLANK=100
######END STUFF THAT MAY NEED CHANGING######

##Get input from command line
#TAXON=$1
GENOME=$1
WORKDIR=$2
CONSENSUSFILE=$3

##Set paths and variables
echo "Genome file is "$GENOME
BASENAME=$(basename $GENOME .gz)
SUBNAME=$(basename $GENOME | awk -F'[.]' '{print $1}')
#SUBNAME=$(basename $GENOME | awk -F'[.]' '{print $1}' | awk -F'[_]' '{print $1}')
TE_ID=$(basename $CONSENSUSFILE | awk -F'.fa' '{print $1}')

echo "Your working directory is "$WORKDIR

##Get RepeatModeler consensus file info
echo "Queries file is "$CONSENSUSFILE
CONSENSUSSEQS=$(basename $CONSENSUSFILE)

#Set up directory structure
mkdir -p $WORKDIR
#THISGENOME=$WORKDIR/${SUBNAME}_N
THISGENOME=$WORKDIR/$TE_ID"_"$SUBNAME
#create a directory for all extension tool work
EXTENSIONWORK=$THISGENOME/extensionwork
mkdir -p $EXTENSIONWORK
#create a directory for extension log files.
EXTENDLOGS=$THISGENOME/extendlogs
mkdir -p $EXTENDLOGS
#create a directory for assembly
GENOMEFILES=$THISGENOME/genomefiles
mkdir -p $GENOMEFILES
#create a folder to store the .png files and MSAs for evaluation
IMAGES=$THISGENOME/images_and_alignments
mkdir -p $IMAGES
#create a folder for potential segmental duplications
SD=$IMAGES/possible_SD
mkdir -p $SD
#create a folder for likely TEs
TE=$IMAGES/likely_TEs
mkdir -p $TE
#create a folder to filter TEs with very few hits
REJECTS=$IMAGES/rejects
mkdir -p $REJECTS
#create a folder to store potential final consensus sequences
FINAL_CONSENSUSES=$THISGENOME/final_consensuses
mkdir -p $FINAL_CONSENSUSES

#Get genome fasta and unzip
echo "Checking genome files"
#if assembly does not exist in this directory, create it
[ ! -f $GENOMEFILES/$SUBNAME".fa" ] && gunzip -c $GENOME.gz > $GENOMEFILES/$SUBNAME".fa"
#[ ! -f $GENOMEFILES/$SUBNAME".fa" ] && cp $GENOME $GENOMEFILES/$SUBNAME".fa"
#if .2bit version of the assembly does not exist, create it.
[ ! -f $GENOMEFILES/$SUBNAME".2bit" ] && $SOFTWARE/faToTwoBit $GENOMEFILES/$SUBNAME".fa" $GENOMEFILES/$SUBNAME".2bit"

#Run blast on queries
echo "Checking blast files"
#if the blast files directory does not exist, create it
[ ! -d $THISGENOME/blastfiles ] && mkdir $THISGENOME/blastfiles
cd $THISGENOME/blastfiles
ln -s $GENOMEFILES/$SUBNAME".fa"
cp $CONSENSUSFILE .
#if blast database doesn't exist, create it
#[ ! -f *.nsq ] && /lustre/work/aosmansk/apps/ncbi-blast-2.11.0+/bin/makeblastdb -in $SUBNAME".fa" -dbtype nucl 
#if blast output doesn't exist, run blast. 
#[ ! -f $SUBNAME"_blastn.out" ] && /lustre/work/aosmansk/apps/ncbi-blast-2.11.0+/bin/blastn -query $CONSENSUSSEQS -db $SUBNAME".fa" -perc_identity 90 -qcov_hsp_perc 90 -outfmt 6 -out $SUBNAME"_blastn.out"

REDUCED_BLAST_DIR="/lustre/scratch/npaulat/RayLib-Masking/filter_blast/filtered_blast90"
cp $REDUCED_BLAST_DIR/$TE_ID/$SUBNAME"_"$TE_ID"_blast90.out" .
REDUCED_BLAST=$SUBNAME"_"$TE_ID"_blast90.out"

#Run extract_align
echo "Running extract_align"
#check if extract_align directory exists
[ ! -d $THISGENOME/extract_align_redo ] && mkdir $THISGENOME/extract_align_redo
cd $THISGENOME/extract_align_redo
ln -s $GENOMEFILES/$SUBNAME".fa"
cp $CONSENSUSFILE .
#run extract_align.pl to pull as many as 50 of the best hits from the blast output out of the genome assembly. Those hits will go into catTEfiles directory. 
#python  $GITPATH/extract_align.py -g $SUBNAME".fa" -b $THISGENOME/blastfiles/$SUBNAME"_blastn.out" -l $CONSENSUSSEQS -lb $SEQBUFFER -rb $SEQBUFFER -n $SEQNUMBER -a n -e n -t n
python $GITPATH/extract_align.py -g $SUBNAME".fa" -b $THISGENOME/blastfiles/$REDUCED_BLAST -l $CONSENSUSSEQS -lb $SEQBUFFER -rb $SEQBUFFER -n $SEQNUMBER -a n -e n -t n

#Run extend tool
echo "Running extension tool"
#for every file in the catTEfiles directory
for FILE in $THISGENOME/extract_align_redo/catTEfiles/*.fa
	# get the name of the TE being examined from the filename
	do TEID=$(basename $FILE | awk -F'.fa' '{print $1}')
	echo "TEID = "$TEID
	#create a diretory for it if it doesn't already exist
	[ ! -d $EXTENSIONWORK/$TEID ] && mkdir $EXTENSIONWORK/$TEID		
	cd $EXTENSIONWORK/$TEID
	#run Robert Hubley's extension tool. Note: original version of this script had option to set '-div 5'. New version has default -div as 18 (see e-mail from Robert, August 1, 2020)
	$EXTENDPATH/davidExtendConsRAM.pl \
		-genome $GENOMEFILES/$SUBNAME".2bit" \
		-family $FILE \
		-outdir . \
		>$EXTENDLOGS/$TEID".extend_redo.log"
	#rename the MSA files and image files with TEID
	sed "s/repam-newrep/$TEID/g" MSA-extended_with_rmod_cons.fa >$TEID"_MSA_extended.fa"
	sed -i "s/CORECONS/CONSENSUS-$TEID/g" $TEID"_MSA_extended.fa"
	sed "s/repam-newrep/$TEID/g" rep >$TEID"_"$SUBNAME"_rep.fa"
	cp img.png $TEID".png"
	#sort elements into categories
	COUNT=$(grep ">" repseq.unextended | wc -l)
	LENGTH=$(grep -v '>' $TEID"_"$SUBNAME"_rep.fa" | wc -m)
	echo "Hit count for $TEID = "$COUNT
	echo "Length of this repeat is = "$LENGTH
	#sort rejects, repeats with fewer than 10 hits
	if test $COUNT -lt 10; then cp $TEID".png" $REJECTS; fi
	if test $COUNT -lt 10; then cp $TEID"_MSA_extended.fa" $REJECTS; fi
	if test $COUNT -gt 9; then cp $TEID"_"$SUBNAME"_rep.fa" $FINAL_CONSENSUSES; fi
	#sort possible segmental duplications, >10,000 bp consensus
	if test $COUNT -gt 9 && test $LENGTH -gt 600; then cp $TEID".png" $SD; fi 
	if test $COUNT -gt 9 && test $LENGTH -gt 600; then cp $TEID"_MSA_extended.fa" $SD; fi 
	if test $COUNT -gt 9 && test $LENGTH -gt 600; then cp $TEID"_"$SUBNAME"_rep.fa" $SD; fi 	
	#sort all other possible TEs
	if test $COUNT -gt 9 && test $LENGTH -lt 10000; then cp $TEID".png" $TE; fi 
	if test $COUNT -gt 9 && test $LENGTH -lt 10000; then cp $TEID"_MSA_extended.fa" $TE; fi
	if test $COUNT -gt 9 && test $LENGTH -lt 10000; then cp $TEID"_"$SUBNAME"_rep.fa" $TE; fi
done

################

#create a directory for all extension tool work
EXTRACTS=$THISGENOME/extracts_redo
mkdir -p $EXTRACTS

#Run modified extract_align to get all blast hit fastas + SEQBUFFER flanks
echo "Running extract_all"
#check if extracts directory exists
[ ! -d $THISGENOME/extracts_redo ] && mkdir $THISGENOME/extracts_redo
cd $THISGENOME/extracts_redo
ln -s $GENOMEFILES/$SUBNAME".fa"
cp $CONSENSUSFILE .
#run extract_align.pl to pull as many as 50 of the best hits from the blast output out of the genome assembly. Those hits will go into catTEfiles directory. 
#python /lustre/scratch/npaulat/yin_yang/extract_all.py -g $SUBNAME".fa" -b $THISGENOME/blastfiles/$SUBNAME"_blastn.out" -l $CONSENSUSSEQS -lb 500 -rb 500 -a n -e n -t n
python /lustre/scratch/npaulat/RayLib-Masking/extract_all.py -g $SUBNAME".fa" -b $THISGENOME/blastfiles/$REDUCED_BLAST -l $CONSENSUSSEQS -lb 500 -rb 500 -a n -e n -t n

