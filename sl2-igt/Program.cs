using System.Diagnostics;
using System.Security.Cryptography;

byte[] AES_KEY = { 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0x32, 0x10 };
const int AES_BLOCK_SIZE = 0x10;
const int SLOT_SIZE = 0x060030;
const int HEADER_SIZE = 0x02C0;
const int READ_OFFSET = AES_BLOCK_SIZE * 1;
const int IGT_BLOCK_OFFSET = 0xC;

var slot = 0; // read from memory
var path = "/home/user/.steam/steam/steamapps/compatdata/570940/pfx/drive_c/users/steamuser/My Documents/NBGI/DARK SOULS REMASTERED/84341421/DRAKS0005.sl2";

int GetIgtNew()
{
    Aes encryptor = Aes.Create();
    encryptor.Mode = CipherMode.CBC;
    encryptor.Padding = PaddingMode.None;

    byte[] cipherBytes = new byte[AES_BLOCK_SIZE * 2];

    var handle = File.OpenHandle(path);
    using (BinaryReader reader = new BinaryReader(new FileStream(handle, FileAccess.Read)))
    {
        reader.BaseStream.Seek(HEADER_SIZE + (slot * SLOT_SIZE) + READ_OFFSET, SeekOrigin.Begin);
        reader.Read(cipherBytes, 0, AES_BLOCK_SIZE * 2);
    }

    byte[] aesKey = new byte[AES_BLOCK_SIZE];
    Array.Copy(AES_KEY, 0, aesKey, 0, AES_BLOCK_SIZE);
    encryptor.Key = aesKey;
    encryptor.IV = cipherBytes.Take(AES_BLOCK_SIZE).ToArray();

    MemoryStream memoryStream = new MemoryStream();
    ICryptoTransform aesDecryptor = encryptor.CreateDecryptor();
    CryptoStream cryptoStream = new CryptoStream(memoryStream, aesDecryptor, CryptoStreamMode.Write);
    byte[] plainBytes;

    try
    {
        cryptoStream.Write(cipherBytes, AES_BLOCK_SIZE, AES_BLOCK_SIZE);
        cryptoStream.FlushFinalBlock();
        plainBytes = memoryStream.ToArray();
    }
    finally
    {
        memoryStream.Close();
        cryptoStream.Close();
    }

    return BitConverter.ToInt32(plainBytes, IGT_BLOCK_OFFSET);
}

int GetIgtOld()
{
    byte[] cipherBytes = File.ReadAllBytes(path);

    Aes encryptor = Aes.Create();
    encryptor.Mode = CipherMode.CBC;

    // Set key and IV
    byte[] aesKey = new byte[16];
    Array.Copy(AES_KEY, 0, aesKey, 0, 16);
    encryptor.Key = aesKey;
    encryptor.IV = cipherBytes.Take(16).ToArray();

    MemoryStream memoryStream = new MemoryStream();
    ICryptoTransform aesDecryptor = encryptor.CreateDecryptor();
    CryptoStream cryptoStream = new CryptoStream(memoryStream, aesDecryptor, CryptoStreamMode.Write);
    byte[] plainBytes;

    try
    {
        cryptoStream.Write(cipherBytes, 0, cipherBytes.Length);
        cryptoStream.FlushFinalBlock();
        plainBytes = memoryStream.ToArray();
    }
    finally
    {
        memoryStream.Close();
        cryptoStream.Close();
    }

    int saveSlotSize = 0x60030;
    int igtOffset = 0x2EC + (saveSlotSize * slot);
    return BitConverter.ToInt32(plainBytes, igtOffset);
}

void PrintIgt(int ms)
{
    TimeSpan t = TimeSpan.FromMilliseconds(ms);
    string answer = string.Format("{0:D2}h:{1:D2}m:{2:D2}s:{3:D3}ms",
                            t.Hours,
                            t.Minutes,
                            t.Seconds,
                            t.Milliseconds);

    Console.WriteLine(answer);
}

const int ITERATIONS = 1000;

void Benchmark(string name, Func<int> fn)
{
    // warmup
    fn();

    var sw = Stopwatch.StartNew();
    for (int i = 0; i < ITERATIONS; i++)
        fn();
    sw.Stop();

    Console.WriteLine($"{name}: {sw.ElapsedMilliseconds}ms total, {sw.Elapsed.TotalMicroseconds / ITERATIONS:F1}µs/iter");
}

Benchmark("Old", GetIgtOld);
Benchmark("New", GetIgtNew);
