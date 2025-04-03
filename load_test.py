import os
import opik
import string
import random
import multiprocessing as mp
import time

def generate_random_string(length):
    characters = string.ascii_letters + string.digits
    return ''.join(random.choice(characters) for _ in range(length))


def log_trace(client):
    trace = client.trace(
        name="demo_trace",
        input={"user_question": generate_random_string(100)},
        output={"output": generate_random_string(50)}
    )

    trace.span(
        name="preprocessing",
        type="general",
        input={"user_question": generate_random_string(100)},
        output={"output": generate_random_string(50)}
    )

    trace.span(
        name="llm_call",
        type="llm",
        input={"user_question": generate_random_string(100)},
        output={"output": generate_random_string(50)}
    )

def log_traces(client, number_of_traces):
    for _ in range(number_of_traces):
        log_trace(client)
    
    client.flush()


def format_elapsed_time(seconds):
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    seconds = seconds % 60
    if hours > 0:
        return f"{hours}h {minutes:02d}m {seconds:05.2f}s"
    elif minutes > 0:
        return f"{minutes}m {seconds:05.2f}s"
    return f"{seconds:.2f}s"

def worker_function(target_traces_per_second):
    os.environ["OPIK_URL_OVERRIDE"] = "http://localhost:5173/api"
    os.environ["OPIK_WORKSPACE"] = "default"
    os.environ["OPIK_API_KEY"] = "BGiEWpBTtYgtEVnoou5KL3JlI"

    client = opik.Opik(
        _use_batching=True,
    )
    total_traces = 0
    process_start_time = time.time()

    for i in range(24 * 60 * 60):
        start_time = time.time()
        log_traces(client, target_traces_per_second)
        if (1 - (time.time() - start_time)) > 0:
            time.sleep(1 - (time.time() - start_time))
        
        total_traces += target_traces_per_second
        elapsed_time = time.time() - process_start_time
        print(f"\rTotal traces: {total_traces*2:,} | Runtime: {format_elapsed_time(elapsed_time)} | Rate: {total_traces/elapsed_time*2:.1f} traces/s", end="", flush=True)
        sleep_time = 1 - (time.time() - start_time)
        if sleep_time > 0:
            time.sleep(sleep_time)

if __name__ == '__main__':
    TARGET_TRACES_PER_SECOND = 1250

    num_processes = 2
    with mp.Pool(processes=num_processes) as pool:
        # Map the worker function across the processes
        pool.map(worker_function, [int(TARGET_TRACES_PER_SECOND / 2)] * num_processes)
