async function request() {
    const res = await fetch("http://127.0.0.1:3000");
    const body = await res.text();
    console.log(body);
}

async function main() {
    const results = await Promise.allSettled(Array.from({ 
        length: 10
    }, () => request()));


    const suc = results.filter((r) => r.status === 'fulfilled');
    const err = results.filter((r) => r.status === 'rejected');
    console.log("Success:", suc.length);
    console.log("Failure:", err.length);
    console.log(err[0]);
}

main();
