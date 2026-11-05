#!/usr/bin/env node
import { TelegramSource } from './telegram-source.mjs';
import { runMessageWorker, reportChannelError } from './message-worker.mjs';

runMessageWorker('telegram', TelegramSource).catch(reportChannelError);
