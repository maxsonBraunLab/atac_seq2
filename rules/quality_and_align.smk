rule trimming:
	input:
		forward_strand = "samples/raw/{sample}_R1.fastq.gz",
		reverse_strand = "samples/raw/{sample}_R2.fastq.gz"
	output:
		forward_paired = "samples/trim/{sample}_R1_fastqc_tpaired.fastq.gz",
		reverse_paired = "samples/trim/{sample}_R2_fastqc_tpaired.fastq.gz",
		forward_unpaired = "samples/trim/{sample}_R1_fastqc_tunpaired.fastq.gz",
		reverse_unpaired = "samples/trim/{sample}_R2_fastqc_tunpaired.fastq.gz",
	params:
		adapter = config["ADAPTERS"]
	conda:
		"../envs/trim.yaml"
	threads: 8
	log: "logs/trimming/{sample}.log"
	message:
		"""--- Trimming ---"""
	shell:
		"""trimmomatic PE -threads {threads} {input.forward_strand} {input.reverse_strand} {output.forward_paired} {output.forward_unpaired} {output.reverse_paired} {output.reverse_unpaired} ILLUMINACLIP:{params.adapter}:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:30"""

rule align:
	input:
		forward_paired = rules.trimming.output.forward_paired,
		reverse_paired = rules.trimming.output.reverse_paired
	output:
		temp("samples/align/bam/{sample}.bam")
	params:
		reference = config["REFERENCE"]
	conda:
		"../envs/bwa.yaml"
	log: "logs/align/{sample}.log"
	message:
		"""--- Aligning reads to reference."""
	threads: 16
	shell:
		"""bwa mem -t {threads} {params.reference} {input.forward_paired} {input.reverse_paired} | samtools view -bS - > {output} """

rule sortbam:
	input:
		rules.align.output
	output:
		"samples/align/sorted/{sample}_sorted.bam"
	conda:
		"../envs/bwa.yaml"
	threads: 4
	message:
		"""--- sorting the bamfile ---"""
	shell:
		"""samtools sort -@ {threads} -o {output} {input}; samtools index {output} """

# -m '2G' = require 2GB of memory to sort for performance gains.

# qc metrics -------------------------------------------------------------------

# QC metrics: fragment length distribution, read mapping proportion per chromosome
rule fragment_length:
	input:
		rules.sortbam.output
	output:
		"samples/align/fragment_length/{sample}.txt"
	conda:
		"../envs/bwa.yaml"
	threads: 4
	shell:
		"samtools view {input} | cut -f9 | awk '$1 > 0 && $1 < 1000' | sort --parallel={threads} -S 50% | uniq -c | sort -b -k2,2n | sed -e 's/^[ \t]*//' > {output}"
# output fragment length info per sample.
# cut -f9 = fragment length in bam file
# awk '$1 > 0' | sort | uniq -c = get positive fragment length, sort, count the lengths
# sort -b -k2,2n = col1 is fragment size, col2 is counts. sort by counts numerically.
# sed = remove tabs

rule fragment_length_plot:
	input:
		expand("samples/align/fragment_length/{sample}.txt", sample = SAMPLE)
	output:
		"samples/align/fragment_length/fragment_length_dist.html"
	run:
		pd.options.plotting.backend = "plotly"
		df = pd.concat([pd.read_csv(f, index_col = 1, sep = " ", names = [f.split('/')[3][:-4]]) for f in input], axis = 1)
		print("Fragment Length Distribution Table")
		print(df)
		fragment_length_dist = df.plot()
		fragment_length_dist.update_layout( 
			title='Fragment Length Distribution', 
			xaxis_title='Fragment Length (bp)', 
			yaxis_title='Counts', 
			legend_title_text='Samples')
		fragment_length_dist.write_html(str(output))
# read in info as list of df. Concat everything into one df (row = length, col = sample, elements = counts of frag length), plot and label with plotly. 