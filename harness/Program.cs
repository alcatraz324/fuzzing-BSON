// harness/Program.cs
// Харнесс для фаззинга библиотеки Newtonsoft.Json.Bson.
// Поддерживает два режима работы:
// 1. AFL++ fork server (при наличии __AFL_SHM_ID) — данные через stdin
// 2. Standalone (coverage, анализ крашей) — данные из файла через аргумент

using System;
using System.IO;
using System.Linq;
using Newtonsoft.Json;
using Newtonsoft.Json.Bson;
using SharpFuzz;

namespace Harness
{
    public static class Program
    {
        public static void Main(string[] args)
        {
            // Проверяем, запущены ли мы под AFL++ fork server
            if (Environment.GetEnvironmentVariable("__AFL_SHM_ID") != null)
            {
                // AFL++ режим: данные приходят через stdin
                // Fuzzer.OutOfProcess.Run запускает fork server и цикл
                Fuzzer.OutOfProcess.Run(stream => RunMode(stream));
            }
            else
            {
                // Standalone режим: данные из файла (для coverlet и анализа крашей)
                if (args.Length < 1)
                {
                    Console.Error.WriteLine("ОШИБКА: Не указан путь к файлу с BSON-данными.");
                    Console.Error.WriteLine("Использование: Harness.<режим> <файл>");
                    Environment.Exit(1);
                }

                using var file = File.OpenRead(args[0]);

                // ВАЖНО: DLL инструментирована через SharpFuzz и содержит вызовы
                // к shared memory AFL++. Без инициализации shared memory через
                // Fuzzer.Run эти вызовы вызывают AccessViolationException.
                // Fuzzer.Run инициализирует shared memory и вызывает callback один раз.
                Fuzzer.Run(_ => RunMode(file));
            }
        }

        private static string GetModeName()
        {
            // В .NET при запуске `dotnet <dll>` массив Environment.GetCommandLineArgs():
            //   cmdArgs[0] = путь к запускаемой DLL (например, "build/Harness.Reader.dll")
            //   cmdArgs[1..] = аргументы приложения (путь к файлу с данными)
            var cmdArgs = Environment.GetCommandLineArgs();

            if (cmdArgs.Length > 0 && !string.IsNullOrEmpty(cmdArgs[0]))
            {
                var name = Path.GetFileNameWithoutExtension(cmdArgs[0]);
                if (!string.IsNullOrEmpty(name))
                    return name;
            }

            return AppDomain.CurrentDomain.FriendlyName;
        }

        private static void RunMode(Stream stream)
        {
            var modeName = GetModeName();

            if (modeName.Contains("Reader"))
                RunReader(stream);
            else if (modeName.Contains("Writer"))
                RunWriter(stream);
            else if (modeName.Contains("Differential"))
                RunDifferential(stream);
            else
                throw new InvalidOperationException(
                    $"Не удалось определить режим. Имя: '{modeName}'. " +
                    $"Аргументы: [{string.Join(", ", Environment.GetCommandLineArgs())}]");
        }

        private static void RunReader(Stream stream)
        {
            try
            {
                using var reader = new BsonDataReader(stream);
                while (reader.Read()) { }
            }
            catch (JsonReaderException) { }
            catch (JsonWriterException) { }
            catch (ArgumentException) { }
            catch (FormatException) { }
            catch (InvalidOperationException) { }
            catch (IOException) { }
            catch (NullReferenceException) { }
        }

        private static void RunWriter(Stream stream)
        {
            try
            {
                using var reader = new BsonDataReader(stream);
                using var outputStream = new MemoryStream();
                using var writer = new BsonDataWriter(outputStream);
                writer.WriteToken(reader);
            }
            catch (JsonReaderException) { }
            catch (JsonWriterException) { }
            catch (ArgumentException) { }
            catch (FormatException) { }
            catch (InvalidOperationException) { }
            catch (IOException) { }
            catch (NullReferenceException) { }
        }

        private static void RunDifferential(Stream stream)
        {
            byte[] bson1;
            try
            {
                using var reader = new BsonDataReader(stream);
                using var outputStream = new MemoryStream();
                using var writer = new BsonDataWriter(outputStream);
                writer.WriteToken(reader);
                writer.Flush();
                bson1 = outputStream.ToArray();
            }
            catch (JsonReaderException) { return; }
            catch (JsonWriterException) { return; }
            catch (ArgumentException) { return; }
            catch (FormatException) { return; }
            catch (InvalidOperationException) { return; }
            catch (IOException) { return; }
            catch (NullReferenceException) { return; }

            byte[] bson2;
            try
            {
                using var inputStream = new MemoryStream(bson1);
                using var reader = new BsonDataReader(inputStream);
                using var outputStream = new MemoryStream();
                using var writer = new BsonDataWriter(outputStream);
                writer.WriteToken(reader);
                writer.Flush();
                bson2 = outputStream.ToArray();
            }
            catch (JsonReaderException) { return; }
            catch (JsonWriterException) { return; }
            catch (ArgumentException) { return; }
            catch (FormatException) { return; }
            catch (InvalidOperationException) { return; }
            catch (IOException) { return; }
            catch (NullReferenceException) { return; }

            if (!bson1.SequenceEqual(bson2))
            {
                Console.Error.WriteLine(
                    $"DIFFERENTIAL: Несоответствие! bson1={bson1.Length} байт, bson2={bson2.Length} байт");
            }
        }
    }
}
