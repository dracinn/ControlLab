using System;
using System.IO.Pipes;

internal static class SpaceStationPipeProbe
{
    private static int Main()
    {
        try
        {
            using (var pipe = new NamedPipeClientStream(
                ".",
                "fcs.sock",
                PipeDirection.InOut,
                PipeOptions.Asynchronous))
            {
                pipe.Connect(3000);
                Console.WriteLine("connected: fcs.sock");
            }

            return 0;
        }
        catch (TimeoutException exception)
        {
            Console.Error.WriteLine("timeout: " + exception.Message);
            return 2;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(
                "failed: " + exception.GetType().FullName + ": " + exception.Message);
            return 1;
        }
    }
}
