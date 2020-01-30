configfile: "config.yaml"

import os
import glob

def get_ids_from_path_pattern(path_pattern):
    ids = sorted([os.path.basename(os.path.splitext(val)[0])
                  for val in (glob.glob(path_pattern))])
    return ids

# Make sure that final_bins/ folder contains all bins in single folder for binIDs
# wildcard to work. Use extractProteinBins rule or perform manually.
binIDs = get_ids_from_path_pattern('final_bins/*.faa')
IDs = get_ids_from_path_pattern('dataset/*')

DATA_READS_1 = f'{config["path"]["root"]}/{config["folder"]["data"]}/{{IDs}}/{{IDs}}_1.fastq.gz'
DATA_READS_2 = f'{config["path"]["root"]}/{config["folder"]["data"]}/{{IDs}}/{{IDs}}_2.fastq.gz'


rule all:
    input:
        expand(f'{config["path"]["root"]}/{config["folder"]["metabat"]}/{{IDs}}/{{IDs}}.metabat-bins', IDs=IDs)
    message:
        """
        WARNING: Be very careful when adding/removing any lines above this message.
        The metaBAGpipes.sh parser is presently hardcoded to edit line 22 of this Snakefile to expand target rules accordingly,
        therefore adding/removing any lines before this message will likely result in parser malfunction.
        """
    shell:
        """
        echo {input}
        """


rule createFolders:
    input:
        config["path"]["root"]
    message:
        """
        Very simple rule to check that the metaBAGpipes.sh parser, Snakefile, and config.yaml file are set up correctly. 
        Generates folders from config.yaml config file, not strictly necessary to run this rule.
        """
    shell:
        """
        cd {input}
        echo -e "Setting up result folders in the following work directory: $(echo {input}) \n"

        # Generate folders.txt by extracting folder names from config.yaml file
        paste config.yaml |cut -d':' -f2|tail -n +4|head -n 19|sed '/^$/d' > folders.txt # NOTE: hardcoded number (19) for folder names, increase number if new folders are introduced.
        
        while read line;do 
            echo "Creating $line folder ... "
            mkdir -p $line;
        done < folders.txt
        
        echo -e "\nDone creating folders. \n"

        rm folders.txt
        """


rule downloadToy:
    input:
        f'{config["path"]["root"]}/{config["folder"]["scripts"]}/{config["scripts"]["toy"]}'
    message:
        """
        Downloads toy dataset into config.yaml data folder and organizes into sample-specific sub-folders.
        Requires download_toydata.txt to be present in scripts folder.
        """
    shell:
        """
        cd {config[path][root]}/{config[folder][data]}

        # Download each link in download_toydata.txt
        echo -e "\nBegin downloading toy dataset ... \n"
        while read line;do 
            wget $line;
        done < {input}
        echo -e "\nDone donwloading dataset.\n"
        
        # Rename downloaded files
        echo -ne "\nRenaming downloaded files ... "
        for file in *;do 
            mv $file ./$(echo $file|sed 's/?download=1//g');
        done
        echo -e " done. \n"

        # Organize data into sample specific sub-folders

        echo -ne "\nGenerating list of unique sample IDs ... "
        for file in *.gz; do 
            echo $file; 
        done | sed 's/_.*$//g' | sed 's/.fastq.gz//g' | uniq > ID_samples.txt
        echo -e " done.\n $(less ID_samples.txt|wc -l) samples identified.\n"

        echo -ne "\nOrganizing downloaded files into sample specific sub-folders ... "
        while read line; do 
            mkdir -p $line; 
            mv $line*.gz $line; 
        done < ID_samples.txt
        echo -e " done. \n"
        
        rm ID_samples.txt
        """


rule organizeData:
    input:
        f'{config["path"]["root"]}/{config["folder"]["data"]}'
    message:
        """
        Sorts paired end raw reads into sample specific sub folders within the dataset folder specified in the config.yaml file.
        Assumes all samples are present in abovementioned dataset folder.
        
        Note: This rule is meant to be run on real datasets. 
        Do not run for toy dataset, as downloadToy rule above sorts the downloaded data already.
        """
    shell:
        """
        cd {input}
    
        echo -ne "\nGenerating list of unique sample IDs ... "

        # Create list of unique sample IDs
        for file in *.gz; do 
            echo $file; 
        done | sed 's/_.*$//g' | sed 's/.fastq.gz//g' | uniq > ID_samples.txt

        echo -e " done.\n $(less ID_samples.txt|wc -l) samples identified.\n"

        # Create folder and move corresponding files for each sample

        echo -ne "\nOrganizing dataset into sample specific sub-folders ... "
        while read line; do 
            mkdir -p $line; 
            mv $line*.gz $line; 
        done < ID_samples.txt
        echo -e " done. \n"
        
        rm ID_samples.txt
        """


rule qfilter: 
    input:
        R1 = DATA_READS_1,
        R2 = DATA_READS_2
    output:
        R1 = f'{config["path"]["root"]}/{config["folder"]["qfiltered"]}/{{IDs}}/{{IDs}}_1.fastq.gz', 
        R2 = f'{config["path"]["root"]}/{config["folder"]["qfiltered"]}/{{IDs}}/{{IDs}}_2.fastq.gz' 
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;

        mkdir -p $(dirname $(dirname {output.R1}))
        mkdir -p $(dirname {output.R1})

        fastp --thread {config[cores][fastp]} \
            -i {input.R1} \
            -I {input.R2} \
            -o {output.R1} \
            -O {output.R2} \
            -j $(dirname {output.R1})/$(echo $(basename $(dirname {output.R1}))).json \
            -h $(dirname {output.R1})/$(echo $(basename $(dirname {output.R1}))).html

        """


rule qfilterVis:
    input: 
        f'{config["path"]["root"]}/{config["folder"]["qfiltered"]}'
    output: 
        text=f'{config["path"]["root"]}/{config["folder"]["stats"]}/qfilter.stats',
        plot=f'{config["path"]["root"]}/{config["folder"]["stats"]}/qfilterVis.pdf',
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p $(dirname {output.text})
        cd {input}

        echo -e "\nGenerating quality filtering results file qfilter.stats: ... "
        for folder in */;do
            for file in $folder*json;do
                ID=$(echo $file|sed 's|/.*$||g')
                readsBF=$(head -n 25 $file|grep total_reads|cut -d ':' -f2|sed 's/,//g'|head -n 1)
                readsAF=$(head -n 25 $file|grep total_reads|cut -d ':' -f2|sed 's/,//g'|tail -n 1)
                basesBF=$(head -n 25 $file|grep total_bases|cut -d ':' -f2|sed 's/,//g'|head -n 1)
                basesAF=$(head -n 25 $file|grep total_bases|cut -d ':' -f2|sed 's/,//g'|tail -n 1)
                q20BF=$(head -n 25 $file|grep q20_rate|cut -d ':' -f2|sed 's/,//g'|head -n 1)
                q20AF=$(head -n 25 $file|grep q20_rate|cut -d ':' -f2|sed 's/,//g'|tail -n 1)
                q30BF=$(head -n 25 $file|grep q30_rate|cut -d ':' -f2|sed 's/,//g'|head -n 1)
                q30AF=$(head -n 25 $file|grep q30_rate|cut -d ':' -f2|sed 's/,//g'|tail -n 1)
                percent=$(awk -v RBF="$readsBF" -v RAF="$readsAF" 'BEGIN{{print RAF/RBF}}' )
                echo "$ID $readsBF $readsAF $basesBF $basesAF $percent $q20BF $q20AF $q30BF $q30AF" >> qfilter.stats
                echo "Sample $ID retained $percent * 100 % of reads ... "
            done
        done

        echo "Done summarizing quality filtering results ... \nMoving to /stats/ folder and running plotting script ... "
        mv qfilter.stats {config[path][root]}/{config[folder][stats]}
        cd {config[path][root]}/{config[folder][stats]}

        Rscript {config[path][root]}/{config[folder][scripts]}/{config[scripts][qfilterVis]}
        echo "Done. "
        rm Rplots.pdf
        """


rule megahit:
    input:
        R1 = rules.qfilter.output.R1, 
        R2 = rules.qfilter.output.R2
    output:
        f'{config["path"]["root"]}/{config["folder"]["assemblies"]}/{{IDs}}/contigs.fasta.gz'
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.megahit.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cd $TMPDIR

        echo -n "Copying qfiltered reads to $TMPDIR ... "
        cp {input.R1} {input.R2} $TMPDIR
        echo "done. "

        echo -n "Running megahit ... "
        megahit -t {config[cores][megahit]} \
            --presets {config[params][assemblyPreset]} \
            --verbose \
            -1 $(basename {input.R1}) \
            -2 $(basename {input.R2}) \
            -o tmp;
        echo "done. "

        echo "Renaming assembly ... "
        mv tmp/final.contigs.fa contigs.fasta
        
        echo "Fixing contig header names: replacing spaces with hyphens ... "
        sed -i 's/ /-/g' contigs.fasta

        echo "Zipping on moving assembly ... "
        gzip contigs.fasta
        mkdir -p $(dirname {output})
        mv contigs.fasta.gz $(dirname {output})
        echo "Done. "
        """


rule assemblyVis:
    input: 
        f'{config["path"]["root"]}/{config["folder"]["assemblies"]}'
    output: 
        text=f'{config["path"]["root"]}/{config["folder"]["stats"]}/assembly.stats',
        plot=f'{config["path"]["root"]}/{config["folder"]["stats"]}/assemblyVis.pdf',
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p $(dirname {output.text})
        cd {input}
    
        echo -e "\nGenerating assembly results file assembly.stats: ... "
        for folder in */;do
            for file in $folder*.gz;do
                ID=$(echo $file|sed 's|/contigs.fasta.gz||g')
                N=$(less $file|grep -c ">");
                L=$(less $file|grep ">"|cut -d '-' -f4|sed 's/len=//'|awk '{{sum+=$1}}END{{print sum}}');
                T=$(less $file|grep ">"|cut -d '-' -f4|sed 's/len=//'|awk '$1>=1000{{c++}} END{{print c+0}}');
                S=$(less $file|grep ">"|cut -d '-' -f4|sed 's/len=//'|awk '$1>=1000'|awk '{{sum+=$1}}END{{print sum}}');
                echo $ID $N $L $T $S>> assembly.stats;
                echo -e "Sample $ID has a total of $L bp across $N contigs, with $S bp present in $T contigs >= 1000 bp ... "
            done;
        done

        echo "Done summarizing assembly results ... \nMoving to /stats/ folder and running plotting script ... "
        mv assembly.stats {config[path][root]}/{config[folder][stats]}
        cd {config[path][root]}/{config[folder][stats]}

        Rscript {config[path][root]}/{config[folder][scripts]}/{config[scripts][assemblyVis]}
        echo "Done. "
        rm Rplots.pdf
        """


rule kallisto:
    input:
        contigs = rules.megahit.output,
        reads = f'{config["path"]["root"]}/{config["folder"]["qfiltered"]}'
    output:
        f'{config["path"]["root"]}/{config["folder"]["concoctInput"]}/{{IDs}}_concoct_inputtableR.tsv'
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.kallisto.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cp {input.contigs} $TMPDIR
        cd $TMPDIR

        echo "Unzipping assembly ... "
        gunzip $(basename {input.contigs})

        echo -e "Done. \nCutting up contigs (default 10kbp chunks) ... "
        cut_up_fasta.py -c {config[params][cutfasta]} -o 0 -m contigs.fasta > assembly_c10k.fa
        
        echo -e "Done. \nIndexing assembly with kallisto ... "
        kallisto index assembly_c10k.fa -i $(basename $(dirname {input.contigs})).kaix

        echo -e "Done. \nPreparing to map against other samples ... "
        for folder in {input.reads}*; do

            echo -e "\nCopying filtered reads to tmpdir ... "
            cp $folder/*.fastq.gz $TMPDIR;
            
            echo -e "\nBegin mapping against focal sample with kallisto ... "
            kallisto quant --threads {config[cores][kallisto]} --plaintext \
                -i $(basename $(dirname {input.contigs})).kaix \
                -o . *_1.fastq.gz *_2.fastq.gz;
            
            echo -e "\nZipping abundance.tsv file ... "
            gzip abundance.tsv;

            echo -e "\nCleaning up ... "
            mv abundance.tsv.gz $(echo $(basename $folder)_abundance.tsv.gz);
            rm *.fastq.gz;
        done
        
        echo -e "\nDone with all mapping steps ... \nGenerating CONCOCT input table from kallisto abundances ... "
        python {config[path][root]}/{config[folder][scripts]}/{config[scripts][kallisto2concoct]} \
            --samplenames <(for s in *abundance.tsv.gz; do echo $s | sed 's/_abundance.tsv.gz//'g; done) *abundance.tsv.gz > $(basename {output})

        sed -i 's/kallisto_coverage_//g' $(basename {output})
        
        mv $(basename {output}) $(dirname {output})
        """


rule concoct:
    input:
        table = rules.kallisto.output,
        contigs = rules.megahit.output
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["concoctOutput"]}/{{IDs}}/{{IDs}}.concoct-bins')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.concoct.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p $(dirname $(dirname {output}))
        cd $TMPDIR
        cp {input.contigs} {input.table} $TMPDIR

        echo "Unzipping assembly ... "
        gunzip $(basename {input.contigs})

        echo -e "Done. \nCutting up contigs (default 10kbp chunks) ... "
        cut_up_fasta.py -c {config[params][cutfasta]} -o 0 -m contigs.fasta > assembly_c10k.fa
        
        echo -e "\nRunning CONCOCT ... "
        concoct --coverage_file {input.table} --composition_file assembly_c10k.fa \
            -b $(basename $(dirname {output})) \
            -t {config[cores][concoct]} \
            -c {config[params][concoct]}
            
        echo -e "\nMerging clustering results into original contigs ... "
        merge_cutup_clustering.py $(basename $(dirname {output}))_clustering_gt1000.csv > $(basename $(dirname {output}))_clustering_merged.csv
        
        echo -e "\nExtracting bins ... "
        mkdir -p $(basename {output})
        extract_fasta_bins.py contigs.fasta $(basename $(dirname {output}))_clustering_merged.csv --output_path $(basename {output})
        
        mkdir -p $(dirname {output})
        mv $(basename {output}) *.txt *.csv $(dirname {output})
        """


rule metabat:
    input:
        assembly = rules.megahit.output,
        R1 = rules.qfilter.output.R1, 
        R2 = rules.qfilter.output.R2
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["metabat"]}/{{IDs}}/{{IDs}}.metabat-bins')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.metabat.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cp {input.assembly} {input.R1} {input.R2} $TMPDIR
        mkdir -p $(dirname $(dirname {output}))
        cd $TMPDIR

        echo "Renaming and unizzping assembly ... "
        mv $(basename {input.assembly}) $(basename $(dirname {input.assembly})).gz
        gunzip $(basename $(dirname {input.assembly})).gz

        echo -e "\nIndexing assembly ... "
        bwa index $(basename $(dirname {input.assembly}))
        
        echo -e "\nMapping sample to assemlby ... "
        bwa mem -t {config[cores][metabat]} $(basename $(dirname {input.assembly})) \
            $(basename {input.R1}) \
            $(basename {input.R2}) > $(basename $(dirname {input.assembly})).sam
        
        echo -e "\nConverting sam to bam with samtools view ... " 
        samtools view -@ {config[cores][metabat]} -Sb $(basename $(dirname {input.assembly})).sam > $(basename $(dirname {input.assembly})).bam

        echo -e "\nSorting sam file with samtools sort ... " 
        samtools sort -@ {config[cores][metabat]} $(basename $(dirname {input.assembly})).bam > $(basename $(dirname {input.assembly})).sort
        
        echo -e "\nRunning metabat2 ... "
        runMetaBat.sh $(basename $(dirname {input.assembly})) $(basename $(dirname {input.assembly})).sort
        
        mkdir -p $(dirname {output})
        mv *.txt $(basename {output}) $(dirname {output})
        """


rule maxbin:
    input:
        assembly = rules.megahit.output,
        R1 = rules.qfilter.output.R1, 
        R2 = rules.qfilter.output.R2
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["maxbin"]}/{{IDs}}/{{IDs}}.maxbin-bins')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.maxbin.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cp {input.assembly} {input.R1} {input.R2} $TMPDIR
        mkdir -p $(dirname $(dirname {output}))
        cd $TMPDIR

        echo "Unzipping assembly ... "
        gunzip contigs.fasta.gz
        
        echo -e "\nRunning maxbin2 ... "
        run_MaxBin.pl -contig contigs.fasta -out $(basename $(dirname {output})) \
            -reads *_1.fastq.gz -reads2 *_2.fastq.gz \
            -thread {config[cores][maxbin]}
        
        rm contigs.fasta *.gz

        mkdir $(basename {output})
        mkdir -p $(dirname {output})

        mv *.fasta $(basename {output})
        mv *.abund1 *.abund2 $(basename {output}) $(dirname {output})
        """


rule binRefine:
    input:
        concoct = f'{config["path"]["root"]}/{config["folder"]["concoctOutput"]}/{{IDs}}/{{IDs}}.concoct-bins',
        metabat = f'{config["path"]["root"]}/{config["folder"]["metabat"]}/{{IDs}}/{{IDs}}.metabat-bins',
        maxbin = f'{config["path"]["root"]}/{config["folder"]["maxbin"]}/{{IDs}}/{{IDs}}.maxbin-bins'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["refined"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.binRefine.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metawrap]};set -u;
        mkdir -p $(dirname {output})
        cd $TMPDIR

        echo "Copying bins from CONCOCT, metabat2, and maxbin2 to tmpdir ... "
        cp -r {input.concoct} {input.metabat} {input.maxbin} $TMPDIR

        echo "Renaming bin folders to avoid errors with metaWRAP ... "
        mv $(basename {input.concoct}) $(echo $(basename {input.concoct})|sed 's/-bins//g')
        mv $(basename {input.metabat}) $(echo $(basename {input.metabat})|sed 's/-bins//g')
        mv $(basename {input.maxbin}) $(echo $(basename {input.maxbin})|sed 's/-bins//g')
        
        echo "Running metaWRAP bin refinement module ... "
        metaWRAP bin_refinement -o . \
            -A $(echo $(basename {input.concoct})|sed 's/-bins//g') \
            -B $(echo $(basename {input.metabat})|sed 's/-bins//g') \
            -C $(echo $(basename {input.maxbin})|sed 's/-bins//g') \
            -t {config[cores][refine]} \
            -m {config[params][refineMem]} \
            -c {config[params][refineComp]} \
            -x {config[params][refineCont]}
 
        rm -r $(echo $(basename {input.concoct})|sed 's/-bins//g') $(echo $(basename {input.metabat})|sed 's/-bins//g') $(echo $(basename {input.maxbin})|sed 's/-bins//g') work_files
        mkdir -p {output}
        mv * {output}
        """


rule binReassemble:
    input:
        R1 = rules.qfilter.output.R1, 
        R2 = rules.qfilter.output.R2,
        refinedBins = rules.binRefine.output
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["reassembled"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.binReassemble.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metawrap]};set -u;
        mkdir -p $(dirname {output})
        cp -r {input.refinedBins}/metawrap_*_bins {input.R1} {input.R2} $TMPDIR
        cd $TMPDIR
        
        echo "Running metaWRAP bin reassembly ... "
        metaWRAP reassemble_bins -o $(basename {output}) \
            -b metawrap_*_bins \
            -1 $(basename {input.R1}) \
            -2 $(basename {input.R2}) \
            -t {config[cores][reassemble]} \
            -m {config[params][reassembleMem]} \
            -c {config[params][reassembleComp]} \
            -x {config[params][reassembleCont]}
        
        rm -r metawrap_*_bins
        rm -r $(basename {output})/work_files
        rm *.fastq.gz 
        mv * $(dirname {output})
        """


rule binningVis:
    input:
        config["path"]["root"]
    message:
        """
        Generate bar plot with number of bins and density plot of bin contigs, 
        total length, completeness, and contamination across different tools.
        """
    shell:
        """
        set +u;source activate {config[envs][metawrap]};set -u;
        
        # READ CONCOCT BINS

        echo "Generating concoct_bins.stats file containing bin ID, number of contigs, and length ... "
        cd {input}/{config[folder][concoctOutput]}
        for folder in */;do 
            var=$(echo $folder|sed 's|/||g'); # Define sample name
            for bin in $folder*concoct-bins/*.fa;do 
                name=$(echo $bin | sed "s|^.*/|$var.bin.|g" | sed 's/.fa//g'); # Define bin name
                N=$(less $bin | grep -c ">");
                L=$(less $bin |grep ">"|cut -d '-' -f4|sed 's/len=//g'|awk '{{sum+=$1}}END{{print sum}}')
                echo "Reading bin $bin ... Contigs: $N , Length: $L "
                echo $name $N $L >> concoct_bins.stats;
            done;
        done
        mv *.stats {input}/{config[folder][reassembled]}
        echo "Done reading CONCOCT bins, moving concoct_bins.stats file to $(echo {input}/{config[folder][reassembled]}) ."

        # READ METABAT2 BINS

        echo "Generating metabat_bins.stats file containing bin ID, number of contigs, and length ... "
        cd {input}/{config[folder][metabat]}
        for folder in */;do 
            var=$(echo $folder | sed 's|/||'); # Define sample name
            for bin in $folder*metabat-bins/*.fa;do 
                name=$(echo $bin|sed 's/.fa//g'|sed 's|^.*/||g'|sed "s/^/$var./g"); # Define bin name
                N=$(less $bin | grep -c ">");
                L=$(less $bin |grep ">"|cut -d '-' -f4|sed 's/len=//g'|awk '{{sum+=$1}}END{{print sum}}')
                echo "Reading bin $bin ... Contigs: $N , Length: $L "
                echo $name $N $L >> metabat_bins.stats;
            done;
        done
        mv *.stats {input}/{config[folder][reassembled]}
        echo "Done reading metabat2 bins, moving metabat_bins.stats file to $(echo {input}/{config[folder][reassembled]}) ."

        # READ MAXBIN2 BINS

        echo "Generating maxbin_bins.stats file containing bin ID, number of contigs, and length ... "
        cd {input}/{config[folder][maxbin]}
        for folder in */;do
            for bin in $folder*maxbin-bins/*.fasta;do 
                name=$(echo $bin | sed 's/.fasta//g' | sed 's|^.*/||g');  # Define bin name
                N=$(less $bin | grep -c ">");
                L=$(less $bin |grep ">"|cut -d '-' -f4|sed 's/len=//g'|awk '{{sum+=$1}}END{{print sum}}')
                echo "Reading bin $bin ... Contigs: $N , Length: $L "
                echo $name $N $L >> maxbin_bins.stats;
            done;
        done
        mv *.stats {input}/{config[folder][reassembled]}
        echo "Done reading maxbin2 bins, moving maxbin_bins.stats file to $(echo {input}/{config[folder][reassembled]}) ."

        # READ METAWRAP REFINED BINS

        echo "Generating refined_bins.stats file containing bin ID, number of contigs, and length ... "
        cd {input}/{config[folder][refined]}
        for folder in */;do 
            samp=$(echo $folder | sed 's|/||'); # Define sample name 
            for bin in $folder*metawrap_*_bins/*.fa;do 
                name=$(echo $bin | sed 's/.fa//g'|sed 's|^.*/||g'|sed "s/^/$samp./g"); # Define bin name
                N=$(less $bin | grep -c ">");
                L=$(less $bin |grep ">"|cut -d '-' -f4|sed 's/len_//g'|awk '{{sum+=$1}}END{{print sum}}')
                echo "Reading bin $bin ... Contigs: $N , Length: $L "
                echo $name $N $L >> refined_bins.stats;
            done;
        done
        echo "Done reading metawrap refined bins ... "

        # READ METAWRAP REFINED CHECKM OUTPUT        
        
        echo "Generating CheckM summary files across samples: concoct.checkm, metabat.checkm, maxbin.checkm, and refined.checkm ... "
        for folder in */;do 
            var=$(echo $folder|sed 's|/||g'); # Define sample name
            paste $folder*concoct.stats|tail -n +2 | sed "s/^/$var.bin./g" >> concoct.checkm
            paste $folder*metabat.stats|tail -n +2 | sed "s/^/$var./g" >> metabat.checkm
            paste $folder*maxbin.stats|tail -n +2 >> maxbin.checkm
            paste $folder*metawrap_*_bins.stats|tail -n +2|sed "s/^/$var./g" >> refined.checkm
        done 
        echo "Done reading metawrap refined output, moving refined_bins.stats, concoct.checkm, metabat.checkm, maxbin.checkm, and refined.checkm files to $(echo {input}/{config[folder][reassembled]}) ."
        mv *.stats *.checkm {input}/{config[folder][reassembled]}

        # READ METAWRAP REASSEMBLED BINS

        echo "Generating reassembled_bins.stats file containing bin ID, number of contigs, and length ... "
        cd {input}/{config[folder][reassembled]}
        for folder in */;do 
            samp=$(echo $folder | sed 's|/||'); # Define sample name 
            for bin in $folder*reassembled_bins/*.fa;do 
                name=$(echo $bin | sed 's/.fa//g' | sed 's|^.*/||g' | sed "s/^/$samp./g"); # Define bin name
                N=$(less $bin | grep -c ">");

                # Need to check if bins are original (megahit-assembled) or strict/permissive (metaspades-assembled)
                if [[ $name == *.strict ]] || [[ $name == *.permissive ]];then
                    L=$(less $bin |grep ">"|cut -d '_' -f4|awk '{{sum+=$1}}END{{print sum}}')
                else
                    L=$(less $bin |grep ">"|cut -d '-' -f4|sed 's/len_//g'|awk '{{sum+=$1}}END{{print sum}}')
                fi

                echo "Reading bin $bin ... Contigs: $N , Length: $L "
                echo $name $N $L >> reassembled_bins.stats;
            done;
        done
        echo "Done reading metawrap reassembled bins ... "

        # READ METAWRAP REFINED CHECKM OUTPUT  

        echo "Generating CheckM summary file reassembled.checkm across samples for reassembled bins ... "
        for folder in */;do 
            var=$(echo $folder|sed 's|/||g');
            paste $folder*reassembled_bins.stats|tail -n +2|sed "s/^/$var./g";
        done >> reassembled.checkm
        echo "Done generating all statistics files for binning results ... running plotting script ... "

        # RUN PLOTTING R SCRIPT

        Rscript {config[path][root]}/{config[folder][scripts]}/{config[scripts][binningVis]}
        rm Rplots.pdf # Delete redundant pdf file
        echo "Done. "
        """


rule classifyGenomes:
    input:
        bins = f'{config["path"]["root"]}/{config["folder"]["reassembled"]}/{{IDs}}/reassembled_bins',
        script = f'{config["path"]["root"]}/{config["folder"]["scripts"]}/classify-genomes'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["classification"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.classify-genomes.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p {output}
        cd $TMPDIR
        cp -r {input.script}/* {input.bins}/* .

        echo "Begin classifying bins ... "
        for bin in *.fa; do
            echo -e "\nClassifying $bin ... "
            $PWD/classify-genomes $bin -t {config[cores][classify]} -o $(echo $bin|sed 's/.fa/.taxonomy/')
            cp *.taxonomy {output}
            rm *.taxonomy
            rm $bin 
        done
        echo "Done classifying bins. "
        """


rule abundance:
    input:
        bins = f'{config["path"]["root"]}/{config["folder"]["reassembled"]}/{{IDs}}/reassembled_bins',
        R1 = rules.qfilter.output.R1, 
        R2 = rules.qfilter.output.R2
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["abundance"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.abundance.benchmark.txt'
    message:
        """
        Calculate bin abundance fraction using the following:

        binAbundanceFraction = (L * X / Y / Z) * 100

        X = # of reads mapped to bin_i from sample_k
        Y = length of bin_i
        Z = # of reads mapped to all bins in sample_k
        L = length of reads (100 bp)
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        mkdir -p {output}
        cd $TMPDIR
        cp {input.bins}/* .
        cat *.fa > $(basename {output}).fa
        cp {input.R1} {input.R2} .
        echo "CREATING INDEX FOR BIN CONCATENATION AND MAPPING READS "
        bwa index $(basename {output}).fa
        bwa mem -t {config[cores][abundance]} $(basename {output}).fa \
            $(basename {input.R1}) $(basename {input.R2}) > $(basename {output}).sam
        samtools view -@ {config[cores][abundance]} -Sb $(basename {output}).sam > $(basename {output}).bam
        samtools sort -@ {config[cores][abundance]} $(basename {output}).bam $(basename {output}).sort
        samtools flagstat $(basename {output}).sort.bam > map.stats
        cp map.stats {output}/$(basename {output})_map.stats
        rm $(basename {output}).fa
        echo "DONE MAPPING READS TO BIN CONCATENATION, BEGIN MAPPING READS TO EACH BIN "
        for bin in *.fa;do
            mkdir -p $(echo "$bin"| sed "s/.fa//")
            mv $bin $(echo "$bin"| sed "s/.fa//")
            cd $(echo "$bin"| sed "s/.fa//")
            echo "INDEXING AND MAPPING BIN $bin "
            bwa index $bin
            bwa mem -t {config[cores][abundance]} $bin \
                ../$(basename {input.R1}) ../$(basename {input.R2}) > $(echo "$bin"|sed "s/.fa/.sam/")
            samtools view -@ {config[cores][abundance]} -Sb $(echo "$bin"|sed "s/.fa/.sam/") > $(echo "$bin"|sed "s/.fa/.bam/")
            samtools sort -@ {config[cores][abundance]} $(echo "$bin"|sed "s/.fa/.bam/") $(echo "$bin"|sed "s/.fa/.sort/")
            samtools flagstat $(echo "$bin"|sed "s/.fa/.sort.bam/") > $(echo "$bin"|sed "s/.fa/.map/")
            echo -n "Bin Length = " >> $(echo "$bin"|sed "s/.fa/.map/")
            less $bin|cut -d '_' -f4| awk -F' ' '{{print $NF}}'|sed 's/len=//'|awk '{{sum+=$NF;}}END{{print sum;}}' >> $(echo "$bin"|sed "s/.fa/.map/")
            echo "FINISHED MAPPING READS TO BIN $bin "
            paste $(echo "$bin"|sed "s/.fa/.map/")
            echo "CALCULATING ABUNDANCE FOR BIN $bin "
            echo -n "$bin"|sed "s/.fa//" >> $(echo "$bin"|sed "s/.fa/.abund/")
            echo -n $'\t' >> $(echo "$bin"|sed "s/.fa/.abund/")
            X=$(less $(echo "$bin"|sed "s/.fa/.map/")|grep "mapped ("|awk -F' ' '{{print $1}}')
            Y=$(less $(echo "$bin"|sed "s/.fa/.map/")|tail -n 1|awk -F' ' '{{print $4}}')
            Z=$(less "../map.stats"|grep "mapped ("|awk -F' ' '{{print $1}}')
            awk -v x="$X" -v y="$Y" -v z="$Z" 'BEGIN{{print (100*x/y/z) * 100}}' >> $(echo "$bin"|sed "s/.fa/.abund/")
            rm $bin
            cp $(echo "$bin"|sed "s/.fa/.map/") {output}
            mv $(echo "$bin"|sed "s/.fa/.abund/") ../
            cd ..
            rm -r $(echo "$bin"| sed "s/.fa//")
        done
        cat *.abund > $(basename {output}).abund
        mv $(basename {output}).abund {output}
        """


rule taxonomyVis:
    shell:
        """
        cd {config[path][root]}/{config[folder][classification]}
        for folder in */;do 
            for file in $folder*.taxonomy;do 
                fasta=$(echo $file | sed 's|^.*/||' | sed 's/.taxonomy//g' | sed 's/.orig//g' | sed 's/.permissive//g' | sed 's/.strict//g'); 
                NCBI=$(less $file | grep NCBI | cut -d ' ' -f4);
                tax=$(less $file | grep tax | sed 's/Consensus taxonomy: //g');
                motu=$(less $file | grep mOTUs | sed 's/Consensus mOTUs: //g');
                detect=$(less $file | grep detected | sed 's/Number of detected genes: //g');
                percent=$(less $file | grep agreeing | sed 's/Percentage of agreeing genes: //g' | sed 's/%//g');
                map=$(less $file | grep mapped | sed 's/Number of mapped genes: //g');
                cog=$(less $file | grep COG | cut -d$'\t' -f1 | tr '\n' ',' | sed 's/,$//g');
                echo -e "$fasta \t $NCBI \t $tax \t $motu \t $detect \t $map \t $percent \t $cog" >> classification.stats;
            done;
        done
        cd {config[path][root]}/{config[folder][abundance]}
        for folder in */;do 
            for file in $folder*.map;do 
                SAMP=$(paste $file | sed -n '1p' | cut -d ' ' -f1);
                BIN=$(paste $file | sed -n '3p' | cut -d ' ' -f1);
                LEN=$(paste $file | sed -n '12p' | cut -d ' ' -f4);
                MAG=$(paste $folder*_map.stats | sed -n '3p' | cut -d ' ' -f1);
                name=$(echo $file | sed 's/.map//g' | sed 's|^.*/||g');
                echo -n "$name ";
                awk -v samp="$SAMP" -v bin="$BIN" -v len="$LEN" 'BEGIN{{printf bin/samp/len}}';
                echo -n " "; 
                awk -v mag="$MAG" -v bin="$BIN" -v len="$LEN" 'BEGIN{{print bin/mag/ len}}';
            done;
        done > abundance.stats

        """


rule extractProteinBins:
    message:
        "Extract ORF annotated protein fasta files for each bin from reassembly checkm files."
    shell:
        """
        cd {config[path][root]}
        mkdir -p {config[folder][finalBins]}

        echo -e "Begin moving and renaming ORF annotated protein fasta bins from reassembled_bins/ to final_bins/ ... \n"
        for folder in reassembled_bins/*/;do 
            echo "Moving bins from sample $(echo $(basename $folder)) ... "
            for bin in $folder*reassembled_bins.checkm/bins/*;do 
            var=$(echo $bin/genes.faa | sed 's|reassembled_bins/||g'|sed 's|/reassembled_bins.checkm/bins||'|sed 's|/genes||g'|sed 's|/|_|g'|sed 's/permissive/p/g'|sed 's/orig/o/g'|sed 's/strict/s/g');
            mv $bin/*.faa {config[path][root]}/{config[folder][finalBins]}/$var;
            done;
        done
        """


rule carveme:
    input:
        bin = f'{config["path"]["root"]}/{config["folder"]["finalBins"]}/{{binIDs}}.faa',
        media = f'{config["path"]["root"]}/{config["folder"]["scripts"]}/{config["scripts"]["carveme"]}'
    output:
        f'{config["path"]["root"]}/{config["folder"]["GEMs"]}/{{binIDs}}.xml'
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{binIDs}}.carveme.benchmark.txt'
    message:
        """
        Make sure that the input files are ORF annotated and preferably protein fasta.
        If given raw fasta files, Carveme will run without errors but each contig will be treated as one gene.
        """
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u
        mkdir -p $(dirname {output})
        cp {input.bin} {input.media} $TMPDIR
        cd $TMPDIR
        
        echo "Begin carving GEM ... "
        carve -g {config[params][carveMedia]} \
            -v \
            --mediadb $(basename {input.media}) \
            --fbc2 \
            -o $(echo $(basename {input.bin}) | sed 's/.faa/.xml/g') $(basename {input.bin})
        
        [ -f *.xml ] && mv *.xml $(dirname {output})
        """


rule modelVis:
    input:
        f'{config["path"]["root"]}/{config["folder"]["GEMs"]}'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u;
        cd {input}
        for folder in ERR*;do 
        for model in $folder/*.xml;do 
        id=$(echo $model|sed 's|^.*/||g'|sed 's/.xml//g'); 
        mets=$(less $model| grep "species id="|cut -d ' ' -f 8|sed 's/..$//g'|sort|uniq|wc -l);
        rxns=$(less $model|grep -c 'reaction id=');
        genes=$(less $model|grep -c 'fbc:geneProduct fbc:id=');
        echo "$id $mets $rxns $genes" >> GEMs.stats;
        done;
        done
        
        Rscript {config[scripts][modelVis]}
        """


rule organizeGEMs:
    message:
        """
        Organizes GEMs into sample specific subfolders. 
        Necessary to run smetana per sample using the {IDs} wildcard.
        One liner (run from refined bins folder): 
        for folder in */;do mkdir -p ../GEMs/$folder;mv ../GEMs/$(echo $folder|sed 's|/||')_*.xml ../GEMs/$folder;done
        """
    shell:
        """
        cd {config[path][refined]}
        for folder in */;do 
        mkdir -p ../{config[path][GEMs]}; 
        mv ../{config[path][GEMs]}/$(echo $folder|sed 's|/||')_*.xml ../{config[path][GEMs]}/$folder;
        done
        """


rule smetana:
    input:
        f'{config["path"]["root"]}/{config["folder"]["GEMs"]}/{{IDs}}'
    output:
        f'{config["path"]["root"]}/{config["folder"]["SMETANA"]}/{{IDs}}_detailed.tsv'
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.smetana.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u
        mkdir -p {config[path][root]}/{config[folder][SMETANA]}
        cp {config[dbs][carveme]} {input}/*.xml $TMPDIR
        cd $TMPDIR
        
        smetana -o $(basename {input}) --flavor fbc2 \
            --mediadb media_db.tsv -m {config[params][smetanaMedia]} \
            --detailed \
            --solver {config[params][smetanaSolver]} -v *.xml
        
        cp *.tsv {config[path][root]} #safety measure for backup of results in case rule fails for some reason
        mv *.tsv $(dirname {output})
        """


rule interactionVis:
    input:
        f'{config["path"]["root"]}/{config["folder"]["SMETANA"]}'
    shell:
        """
        cd {input}
        mv media_db.tsv ../scripts/
        cat *.tsv|sed '/community/d' > smetana.all
        less smetana.all |cut -f2|sort|uniq > media.txt
        ll|grep tsv|awk '{print $NF}'|sed 's/_.*$//g'>samples.txt
        while read sample;do echo -n "$sample ";while read media;do var=$(less smetana.all|grep $sample|grep -c $media); echo -n "$var " ;done < media.txt; echo "";done < samples.txt > sampleMedia.stats
        """


rule memote:
    input:
        f'{config["path"]["root"]}/{config["folder"]["GEMs"]}/{{IDs}}'
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["memote"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.memote.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u

        mkdir -p $(dirname {output})
        mkdir -p {output}
        
        cp {input}/*.xml $TMPDIR
        cd $TMPDIR
        
        for model in *.xml;do
            memote report snapshot --filename $(echo $model|sed 's/.xml/.html/') $model
            memote run $model > $(echo $model|sed 's/.xml/-summary.txt/')
            mv *.txt *.html {output}
            rm $model
        done
        """


rule grid:
    input:
        bins = f'{config["path"]["root"]}/{config["folder"]["reassembled"]}/{{IDs}}/reassembled_bins',
        R1 = rules.qfilter.output.R1, 
        R2 = rules.qfilter.output.R2
    output:
        directory(f'{config["path"]["root"]}/{config["folder"]["GRiD"]}/{{IDs}}')
    benchmark:
        f'{config["path"]["root"]}/benchmarks/{{IDs}}.grid.benchmark.txt'
    shell:
        """
        set +u;source activate {config[envs][metabagpipes]};set -u

        cp -r {input.bins} {input.R1} {input.R2} $TMPDIR
        cd $TMPDIR

        cat *.gz > $(basename $(dirname {input.bins})).fastq.gz
        rm $(basename {input.R1}) $(basename {input.R2})

        mkdir MAGdb out
        update_database -d MAGdb -g $(basename {input.bins}) -p MAGdb
        rm -r $(basename {input.bins})

        grid multiplex -r . -e fastq.gz -d MAGdb -p -c 0.2 -o out -n {config[cores][grid]}

        rm $(basename $(dirname {input.bins})).fastq.gz
        mkdir {output}
        mv out/* {output}
        """

