export train_cmd="queue.pl --mem 8G"
export cuda_cmd="queue.pl --gpu 1 --mem 10G"
export decode_cmd="queue.pl --decode_gpu 1 --mem 16G"
export dgx_cuda_cmd="queue.pl --gpu 1 --mem 10G -q gpu.q@@dgx"

