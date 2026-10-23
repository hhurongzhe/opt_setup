#!/bin/bash
#SBATCH --account=rrg-holt
#SBATCH -J make
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32

#sh make_boost.sh
#sh make_fftw.sh
#sh make_gsl.sh
#sh make_hdf5.sh
sh make_openblas.sh
#sh make_openmpi.sh