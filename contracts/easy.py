import pprint

def balanceWhite():
    return {'ETH': 0, 'XRP': 0, 'ADA': 0}


def balanceRisky():
    return {'ETH': 0, 'SPHERE': 0}


user1 = 'user1'
user2 = 'user2'
user3 = 'user3'

whitePool = {
    user1: balanceWhite(),
    user2: balanceWhite(),
    user3: balanceWhite(),
}


riskyPool = {
    user1: balanceRisky(),
    user2: balanceRisky(),
    user3: balanceRisky(),
}


def pool_total(pool):
    result = {}
    for user, balance in pool.items():
        for token, amount in balance.items():
            if token in result:
                result[token] += amount
            else:
                result[token] = amount
    return result


def traderSwap(pool, token0, token0amount, token1, token1amount):
    assert (token0amount < 0 and token1amount > 0) or (token1amount < 0 and token0amount > 0)
    total = pool_total(pool)
    if token0amount < 0:
        assert total[token0] >= abs(token0amount)
    if token1amount < 0:
        assert total[token1] >= abs(token1amount)

    if token0amount < 0:
        shares = {
            user: pool[user][token0] / total[token0]
            for user in pool
        }
    if token1amount < 0:
        shares = {
            user: pool[user][token1] / total[token1]
            for user in pool
        }

    for user, balances in pool.items():
        balances[token0] += shares[user] * token0amount
        balances[token1] += shares[user] * token1amount


def show(t):
    print(f'==== t={t} ====')

    print(f'whitePool:')
    pprint.pprint(whitePool, sort_dicts=False)
    print(f'total: {pool_total(whitePool)}')

    print(f'riskyPool:')
    pprint.pprint(riskyPool, sort_dicts=False)
    print(f'total: {pool_total(riskyPool)}')
    print('')


whitePool[user1]['ETH'] = 400
whitePool[user2]['ETH'] = 400
whitePool[user3]['ETH'] = 400

if 0:
    show(0)
    traderSwap(whitePool, 'ETH', -300, 'XRP', 300)
    show(1)
    whitePool[user1]['ETH'] -= 150
    riskyPool[user1]['ETH'] += 150
    whitePool[user2]['ETH'] -= 150
    riskyPool[user2]['ETH'] += 150
    show(2)
    traderSwap(whitePool, 'ETH', -300, 'XRP', 300)
    show(3)
    traderSwap(riskyPool, 'ETH', -100, 'SPHERE', 100)
    show(4)
    whitePool[user1]['ETH'] += 50
    riskyPool[user1]['ETH'] -= 50
    show(5)
    traderSwap(whitePool, 'XRP', -300, 'ADA', 300)
    show(6)


show(0)
whitePool[user1]['ETH'] -= 400
riskyPool[user1]['ETH'] += 400
traderSwap(riskyPool, 'ETH', -400, 'SPHERE', 400)
show(1)
traderSwap(whitePool, 'ETH', -400, 'XRP', 400)
show(2)
traderSwap(riskyPool, 'ETH', 400, 'SPHERE', -400)
whitePool[user1]['ETH'] += 400
riskyPool[user1]['ETH'] -= 400
show(3)
whitePool[user2]['ETH'] -= 200
riskyPool[user2]['ETH'] += 200
traderSwap(riskyPool, 'ETH', -200, 'SPHERE', 200)
show(4)
traderSwap(whitePool, 'ETH', -400, 'ADA', 400)
show(5)

for i in range(30):
    import random
    while 1:
        amount = random.randint(1,3)*100
        tokens = list(balanceWhite())
        token0 = random.choice(tokens)
        token1 = random.choice([_ for _ in tokens if _ != token0])
        total = pool_total(whitePool)
        if total[token0] >= amount:
            break
    print(f'swap {amount} {token0} -> {amount} {token1}')
    traderSwap(whitePool, token0, -amount, token1, amount)

show(6)
