#!/home/cadrianmae/.pyenv/versions/3.11.13/bin/python
import argparse
import os
import logging
from openai import OpenAI
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

def setup_logging():
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s %(levelname)s: %(message)s',
    )

def parse_args():
    parser = argparse.ArgumentParser(description="Transcribe audio files using OpenAI GPT-4o.")
    parser.add_argument("files", nargs='+', help="Audio file paths to transcribe.")
    parser.add_argument("--parallel", action="store_true", help="Process files in parallel.")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--srt", action="store_true", help="Output transcription in SRT subtitle format.")
    group.add_argument("--llm-process", action="store_true", help="Post-process transcription with LLM.")
    return parser.parse_args()

def transcribe_file(client, file_path):
    logging.info(f"Transcribing file: {file_path}")
    with open(file_path, "rb") as audio_file:
        transcription = client.audio.transcriptions.create(
            model="gpt-4o-transcribe",
            file=audio_file
        )
    logging.debug(f"Transcription complete for: {file_path}")
    return transcription.text

def transcribe_file_srt(client, file_path):
    logging.info(f"Transcribing file to SRT: {file_path}")
    with open(file_path, "rb") as audio_file:
        transcription = client.audio.transcriptions.create(
            model="whisper-1",
            response_format="srt",
            file=audio_file
        )
    logging.debug(f"Transcription complete for SRT: {file_path}")
    logging.debug(f"SRT Content: {transcription}")
    return transcription


def get_output_path(input_path, extension=".txt"):
    base, _ = os.path.splitext(input_path)
    return base + extension

def save_transcription(text, out_path):
    logging.info(f"Saving transcription to: {out_path}")
    with open(out_path, "w", encoding="utf-8") as out_file:
        out_file.write(text)
    logging.debug(f"Saved transcription to: {out_path}")

def process_transcription(client, text):
    logging.info("Processing transcription for clarity and grammar.")
    response = client.responses.create(
        model="gpt-5-nano",
        instructions="Improve the clarity and grammar of the following transcription. Return only the improved text.",
        input=text
    )
    logging.debug("Processing complete.")
    return response.output_text

def process_single_file(client, file_path):
    logging.info(f"Starting processing for: {file_path}")
    try:
        if process_single_file.srt:
            out_path = get_output_path(file_path, extension=".srt")
            srt_text = transcribe_file_srt(client, file_path)
            save_transcription(srt_text, out_path)
        else:
            out_path = get_output_path(file_path)
            text = transcribe_file(client, file_path)
            if process_single_file.llm_process:
                processed_text = process_transcription(client, text)
                save_transcription(processed_text, out_path)
            else:
                save_transcription(text, out_path)
        logging.debug(f"Transcription saved to {out_path}")
    except Exception as e:
        logging.error(f"Error transcribing {file_path}: {e}")

def process_files(client, files, max_workers=4):
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(process_single_file, client, file_path): file_path for file_path in files}
        with tqdm(total=len(files), desc="Transcribing", position=0, leave=True) as pbar:
            for future in as_completed(futures):
                file_path = futures[future]
                try:
                    future.result()
                except Exception as exc:
                    logging.error(f"Unhandled error in processing {file_path}: {exc}")
                pbar.update(1)


def main():
    setup_logging()
    args = parse_args()
    client = OpenAI()
    # Set flags for processing
    process_single_file.llm_process = args.llm_process
    process_single_file.srt = args.srt
    if args.parallel:
        process_files(client, args.files)
    else:
        with tqdm(total=len(args.files), desc="Transcribing", position=0, leave=True) as pbar:
            for file_path in args.files:
                process_single_file(client, file_path)
                pbar.update(1)

if __name__ == "__main__":
    main()
